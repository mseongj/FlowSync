import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flow_sync/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:flow_sync/features/auth/data/repositories/auth_repository.dart';
import 'package:flow_sync/features/auth/presentation/bloc/auth_bloc.dart';
import 'injection.dart';

/// Registers auth-layer dependencies that depend on [SupabaseClient],
/// which is only available after `Supabase.initialize()` completes at runtime.
/// Other auth services (SecureStorageRepository, KeyDerivationService,
/// CryptoWorkerManager) are auto-registered via @lazySingleton annotations.
void setupAuthInjection() {
  getIt.registerLazySingleton<IAuthRepository>(() => AuthRepository(getIt()));
  getIt.registerLazySingleton(() => AuthBloc(getIt()));
}
