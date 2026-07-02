import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../errors/failures.dart';
import '../session/session_storage.dart';
import '../session/user_role.dart';

/// Thin wrapper around Odoo's JSON-RPC endpoint.
///
/// All Odoo network traffic goes through this class. The cookie jar is
/// disk-backed on native (`PersistCookieJar`) so the `session_id` cookie
/// survives app restarts — that's what makes "stay signed in" work.
class OdooClient {
  final Dio _dio;
  final CookieJar _jar;
  final SessionStorage _session;

  OdooClient._(this._dio, this._jar, this._session);

  factory OdooClient.create(SessionStorage session, CookieJar jar) {
    final dio = Dio(
      BaseOptions(
        baseUrl: kIsWeb ? '' : AppConfig.serverUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        contentType: 'application/json',
        responseType: ResponseType.json,
        extra: kIsWeb ? {'withCredentials': true} : {},
      ),
    );
    if (!kIsWeb) {
      dio.interceptors.add(CookieManager(jar));
    }
    return OdooClient._(dio, jar, session);
  }

  /// Builds the cookie jar the client will use. Persistent on native so
  /// closing the app doesn't drop the Odoo session.
  static Future<CookieJar> createCookieJar() async {
    if (kIsWeb) return CookieJar();
    final dir = await getApplicationDocumentsDirectory();
    return PersistCookieJar(storage: FileStorage('${dir.path}/.odoo_cookies/'));
  }

  Future<int> authenticate({
    required String db,
    required String login,
    required String password,
  }) async {
    final data = await _post('/web/session/authenticate', {
      'db': db,
      'login': login,
      'password': password,
    });
    if (data is! Map || data['uid'] == null || data['uid'] == false) {
      throw const AuthFailure('Invalid login or password.');
    }
    final uid = data['uid'] as int;
    final name = (data['name'] as String?) ?? login;
    final isInternalUser = data['is_internal_user'] == true;
    final isPortal = !isInternalUser;

    String sessionValue = 'web-managed';
    if (!kIsWeb) {
      final cookies = await _jar.loadForRequest(Uri.parse(AppConfig.serverUrl));
      final cookie = cookies.firstWhere(
        (c) => c.name == 'session_id',
        orElse: () => throw const AuthFailure('No session cookie returned.'),
      );
      sessionValue = cookie.value;
    }

    // Save the coarse metadata now so downstream RPCs can use the cookie;
    // then fetch groups (best-effort) so we can classify the role.
    await _session.saveSession(
      sessionId: sessionValue,
      database: db,
      login: login,
      uid: uid,
      userName: name,
      isPortal: isPortal,
    );

    await _classifyAndSaveRole(uid, isInternalUser: isInternalUser);
    return uid;
  }

  /// Reads the user's group names and derives a [UserRole]. Silently
  /// falls back to a portal-safe default if the reads fail — the base
  /// isPortal flag still routes the user correctly, this just narrows
  /// admin ↔ teacher ↔ student ↔ parent.
  ///
  /// Odoo 19 renamed the field: `groups_id` → `all_group_ids` (transitive,
  /// includes implied groups) and `group_ids` (direct only). We ask for
  /// the transitive one and fall through to the direct one on older
  /// installs.
  Future<void> _classifyAndSaveRole(
    int uid, {
    required bool isInternalUser,
  }) async {
    try {
      List<int> ids = const [];
      for (final field in const ['all_group_ids', 'group_ids', 'groups_id']) {
        try {
          final rows = await callKw<List<dynamic>>(
            model: 'res.users',
            method: 'read',
            args: [
              [uid],
              [field],
            ],
          );
          if (rows.isNotEmpty && rows.first is Map) {
            final raw = ((rows.first as Map)[field] as List?) ?? const [];
            ids = raw.whereType<num>().map((n) => n.toInt()).toList();
            if (ids.isNotEmpty) break;
          }
        } catch (_) {
          // Field doesn't exist on this Odoo version — try the next.
        }
      }

      final groupRows = ids.isEmpty
          ? const <dynamic>[]
          : await callKw<List<dynamic>>(
              model: 'res.groups',
              method: 'read',
              args: [
                ids,
                const ['full_name', 'name'],
              ],
            );
      final names = <String>[];
      for (final g in groupRows) {
        if (g is Map) {
          final full = g['full_name']?.toString() ?? '';
          if (full.isNotEmpty) {
            names.add(full);
          } else {
            names.add(g['name']?.toString() ?? '');
          }
        }
      }
      final role = UserRole.classify(names, isInternalUser: isInternalUser);
      await _session.saveRole(role);
    } catch (_) {
      await _session.saveRole(
        isInternalUser ? UserRole.unknown : UserRole.student,
      );
    }
  }

  Future<void> logout() async {
    try {
      await _post('/web/session/destroy', {});
    } catch (_) {
      // Best-effort — always clear local state.
    }
    await _session.clear();
    if (!kIsWeb) _jar.deleteAll();
  }

  /// Generic Odoo `call_kw` RPC. Callers pass the model + method plus the
  /// positional [args] Odoo expects and optional [kwargs]; the decoded
  /// `result` is returned as [T].
  Future<T> callKw<T>({
    required String model,
    required String method,
    required List<dynamic> args,
    Map<String, dynamic> kwargs = const {},
  }) async {
    final result = await _post('/web/dataset/call_kw', {
      'model': model,
      'method': method,
      'args': args,
      'kwargs': kwargs,
    });
    return result as T;
  }

  Future<dynamic> _post(String path, Map<String, dynamic> params) async {
    try {
      final body = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': params,
      });
      final response = await _dio.post(
        path,
        data: body,
        options: Options(
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        ),
      );
      final responseBody = response.data;
      if (responseBody is Map && responseBody.containsKey('error')) {
        final err = responseBody['error'];
        String? msg;
        if (err is Map) {
          final data = err['data'];
          if (data is Map) msg = data['message']?.toString();
          msg ??= err['message']?.toString();
        }
        throw ServerFailure(msg ?? err.toString());
      }
      return responseBody is Map ? responseBody['result'] : responseBody;
    } on DioException catch (e) {
      throw ServerFailure(_friendlyDioMessage(e));
    }
  }

  String _friendlyDioMessage(DioException e) {
    final body = e.response?.data;
    if (body is Map) {
      final err = body['error'];
      if (err is Map) {
        final data = err['data'];
        if (data is Map) {
          final msg = data['message'];
          if (msg is String && msg.isNotEmpty) return msg;
        }
        final m = err['message'];
        if (m is String && m.isNotEmpty) return m;
      }
    }
    final code = e.response?.statusCode;
    if (code != null) return 'Server returned HTTP $code.';
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'Connection timed out. Check your network and try again.',
      DioExceptionType.connectionError =>
        'Could not reach the server. Check your network connection.',
      DioExceptionType.badCertificate => 'Server certificate is invalid.',
      DioExceptionType.cancel => 'Request cancelled.',
      _ => 'Network error. Please try again.',
    };
  }
}
