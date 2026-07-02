import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/odoo_edu_colors.dart';
import 'features/auth/auth_bloc.dart';
import 'injection_container.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  await configureDependencies();
  runApp(const EduErpApp());
}

class EduErpApp extends StatefulWidget {
  const EduErpApp({super.key});

  @override
  State<EduErpApp> createState() => _EduErpAppState();
}

class _EduErpAppState extends State<EduErpApp> {
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthBloc>(
      create: (_) => sl<AuthBloc>(),
      child: MaterialApp.router(
        title: 'EduERP',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(seedColor: OdooEduColors.brand),
          appBarTheme: const AppBarTheme(
            backgroundColor: OdooEduColors.brand,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
        routerConfig: _router,
      ),
    );
  }
}
