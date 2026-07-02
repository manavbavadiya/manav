import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/failures.dart';
import '../../core/network/odoo_client.dart';
import '../../core/session/session_storage.dart';
import '../../core/session/user_role.dart';

// ── Events ───────────────────────────────────────────────────────────────────

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => const [];
}

class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

class AuthLoginRequested extends AuthEvent {
  const AuthLoginRequested({required this.login, required this.password});
  final String login;
  final String password;

  @override
  List<Object?> get props => [login, password];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

// ── States ───────────────────────────────────────────────────────────────────

class AuthSession extends Equatable {
  const AuthSession({
    required this.database,
    required this.login,
    required this.uid,
    required this.userName,
    required this.isPortal,
    required this.role,
  });

  final String database;
  final String login;
  final int uid;
  final String userName;
  final bool isPortal;
  final UserRole role;

  @override
  List<Object?> get props => [database, login, uid, userName, isPortal, role];
}

abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => const [];
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class Authenticated extends AuthState {
  const Authenticated(this.session);
  final AuthSession session;

  @override
  List<Object?> get props => [session];
}

class Unauthenticated extends AuthState {
  const Unauthenticated();
}

class AuthError extends AuthState {
  const AuthError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

// ── Bloc ─────────────────────────────────────────────────────────────────────

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required OdooClient client, required SessionStorage session})
    : _client = client,
      _session = session,
      super(const AuthUnknown()) {
    on<AuthCheckRequested>(_onCheck);
    on<AuthLoginRequested>(_onLogin);
    on<AuthLogoutRequested>(_onLogout);
  }

  final OdooClient _client;
  final SessionStorage _session;

  Future<void> _onCheck(AuthCheckRequested e, Emitter<AuthState> emit) async {
    emit(const AuthLoading());
    final has = await _session.hasSession();
    if (!has) {
      emit(const Unauthenticated());
      return;
    }
    final meta = await _session.getMeta();
    if (meta.uid == null || meta.database == null) {
      emit(const Unauthenticated());
      return;
    }
    emit(
      Authenticated(
        AuthSession(
          database: meta.database!,
          login: meta.login ?? '',
          uid: meta.uid!,
          userName: meta.userName ?? '',
          isPortal: meta.isPortal,
          role: meta.role,
        ),
      ),
    );
  }

  Future<void> _onLogin(AuthLoginRequested e, Emitter<AuthState> emit) async {
    emit(const AuthLoading());
    try {
      await _client.authenticate(
        db: AppConfig.defaultDatabase,
        login: e.login,
        password: e.password,
      );
      final meta = await _session.getMeta();
      emit(
        Authenticated(
          AuthSession(
            database: meta.database!,
            login: meta.login!,
            uid: meta.uid!,
            userName: meta.userName ?? '',
            isPortal: meta.isPortal,
            role: meta.role,
          ),
        ),
      );
    } on Failure catch (f) {
      emit(AuthError(f.message));
    } catch (err) {
      emit(AuthError(err.toString()));
    }
  }

  Future<void> _onLogout(AuthLogoutRequested e, Emitter<AuthState> emit) async {
    emit(const AuthLoading());
    await _client.logout();
    emit(const Unauthenticated());
  }
}
