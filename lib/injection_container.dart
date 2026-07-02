import 'package:cookie_jar/cookie_jar.dart';
import 'package:get_it/get_it.dart';

import 'core/network/odoo_client.dart';
import 'core/session/session_storage.dart';
import 'features/auth/auth_bloc.dart';
import 'features/home/data/module_remote_datasource.dart';
import 'features/home/data/student_profile_datasource.dart';
import 'features/home/presentation/module_grid_bloc.dart';

final GetIt sl = GetIt.instance;

Future<void> configureDependencies() async {
  sl.registerLazySingleton<SessionStorage>(() => SessionStorage());

  // Persistent cookie jar has to be built eagerly (needs an awaited
  // path_provider call) — wire it up before OdooClient.
  final cookieJar = await OdooClient.createCookieJar();
  sl.registerSingleton<CookieJar>(cookieJar);

  sl.registerLazySingleton<OdooClient>(() => OdooClient.create(sl(), sl()));

  sl.registerFactory<AuthBloc>(() => AuthBloc(client: sl(), session: sl()));

  // Module tree — used by drawer + module grid.
  sl.registerLazySingleton<ModuleRemoteDataSource>(
    () => ModuleRemoteDataSource(sl()),
  );
  sl.registerFactory<ModuleGridBloc>(() => ModuleGridBloc(sl()));

  sl.registerLazySingleton<StudentProfileDataSource>(
    () => StudentProfileDataSource(sl(), sl()),
  );
}
