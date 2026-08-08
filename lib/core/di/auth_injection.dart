import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flow_sync/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:flow_sync/features/auth/data/repositories/auth_repository.dart';
import 'package:flow_sync/features/auth/data/crypto/secure_storage_repository.dart';
import 'package:flow_sync/features/auth/data/crypto/key_derivation_service.dart';
import 'package:flow_sync/features/auth/data/crypto/crypto_worker.dart';
import 'package:flow_sync/features/auth/presentation/bloc/auth_bloc.dart';
import 'injection.dart';

void setupAuthInjection() {
  // FlutterSecureStorage is already registered in injection.config.dart init()

  // Repositories & Services
  getIt.registerLazySingleton<IAuthRepository>(() => AuthRepository(getIt()));
  getIt.registerLazySingleton(() => SecureStorageRepository());
  getIt.registerLazySingleton(() => KeyDerivationService());

  // Singleton Worker Manager (Keeps keys in memory)
  getIt.registerSingleton<CryptoWorkerManager>(CryptoWorkerManager());

  // Blocs
  getIt.registerLazySingleton(() => AuthBloc(getIt()));
}
