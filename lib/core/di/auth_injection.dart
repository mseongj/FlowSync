import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flow_sync/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:flow_sync/features/auth/data/repositories/auth_repository.dart';
import 'package:flow_sync/features/auth/data/crypto/secure_storage_repository.dart';
import 'package:flow_sync/features/auth/data/crypto/key_derivation_service.dart';
import 'package:flow_sync/features/auth/data/crypto/crypto_worker.dart';
import 'package:flow_sync/features/auth/presentation/bloc/auth_bloc.dart';

final sl = GetIt.instance;

void setupAuthInjection() {
  // Supabase Client
  sl.registerLazySingleton(() => Supabase.instance.client);

  // Repositories & Services
  sl.registerLazySingleton<IAuthRepository>(() => AuthRepository(sl()));
  sl.registerLazySingleton(() => SecureStorageRepository());
  sl.registerLazySingleton(() => KeyDerivationService());
  
  // Singleton Worker Manager (Keeps keys in memory)
  sl.registerSingleton<CryptoWorkerManager>(CryptoWorkerManager());

  // Blocs
  sl.registerFactory(() => AuthBloc(sl()));
}
