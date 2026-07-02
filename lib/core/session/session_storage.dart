import 'package:shared_preferences/shared_preferences.dart';

import 'user_role.dart';

/// Persists a minimum viable "signed-in" fingerprint on disk so the app can
/// skip the login screen the next time it's launched. The actual Odoo
/// session cookie lives in the cookie jar (`PersistCookieJar`); this stores
/// the human-readable metadata we need to route the user post-login.
class SessionStorage {
  static const _kSessionId = 'odoo_session_id';
  static const _kDatabase = 'odoo_database';
  static const _kLogin = 'odoo_login';
  static const _kUid = 'odoo_uid';
  static const _kUserName = 'odoo_username';
  static const _kIsPortal = 'odoo_is_portal';
  static const _kRole = 'odoo_role';

  Future<void> saveSession({
    required String sessionId,
    required String database,
    required String login,
    required int uid,
    required String userName,
    required bool isPortal,
    UserRole? role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSessionId, sessionId);
    await prefs.setString(_kDatabase, database);
    await prefs.setString(_kLogin, login);
    await prefs.setInt(_kUid, uid);
    await prefs.setString(_kUserName, userName);
    await prefs.setBool(_kIsPortal, isPortal);
    if (role != null) {
      await prefs.setString(_kRole, role.storageKey);
    }
  }

  Future<void> saveRole(UserRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRole, role.storageKey);
  }

  Future<String?> getSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSessionId);
  }

  Future<
    ({
      String? database,
      String? login,
      int? uid,
      String? userName,
      bool isPortal,
      UserRole role,
    })
  >
  getMeta() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      database: prefs.getString(_kDatabase),
      login: prefs.getString(_kLogin),
      uid: prefs.getInt(_kUid),
      userName: prefs.getString(_kUserName),
      isPortal: prefs.getBool(_kIsPortal) ?? true,
      role: UserRole.fromStorage(prefs.getString(_kRole)),
    );
  }

  Future<bool> hasSession() async => (await getSessionId()) != null;

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionId);
    await prefs.remove(_kDatabase);
    await prefs.remove(_kLogin);
    await prefs.remove(_kUid);
    await prefs.remove(_kUserName);
    await prefs.remove(_kIsPortal);
    await prefs.remove(_kRole);
  }
}
