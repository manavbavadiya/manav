import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/odoo_edu_colors.dart';
import 'auth_bloc.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthBloc>().add(const AuthCheckRequested());
    });
  }

  /// Auth check → decide where to route:
  ///   1. Already signed in → straight to `/admin` or `/portal` (role
  ///      decides). "Stay signed in" beats the walkthrough.
  ///   2. Signed out → run the full 5-step pre-login flow every time:
  ///      onboarding page 1 → 2 → 3 → server_config → login.
  Future<void> _route(BuildContext context, AuthState state) async {
    if (state is Authenticated) {
      if (AppConfig.serverUrl.isEmpty) await AppConfig.load();
      if (context.mounted) context.go(state.session.role.postLoginRoute);
      return;
    }
    if (state is Unauthenticated || state is AuthError) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('onboarding_completed');
      if (context.mounted) context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: _route,
      child: const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.school, size: 84, color: OdooEduColors.brand),
              SizedBox(height: 24),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(OdooEduColors.brand),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
