import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import 'core/config/env.dart';
import 'core/di/injection.dart';
import 'core/di/auth_injection.dart';
import 'core/database/local_database_service.dart';
import 'core/background/sync_queue_manager.dart';
import 'core/theme/cubit/theme_cubit.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/domain/repositories/i_auth_repository.dart';
import 'features/auth/domain/entities/auth_user.dart';
import 'features/nlp/presentation/bloc/nlp_input_bloc.dart';
import 'features/schedule/presentation/bloc/schedule_bloc.dart';

void main() {
  // 1. Flutter Binding
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Run App Immediately to avoid ANR
  runApp(const AppInitializer());
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 3. DI Setup
    configureDependencies();

    // 4. Eagerly init Local DB
    await getIt<LocalDatabaseService>().initialize();

    // 5. Initialize Supabase Client
    var supabaseReady = false;
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
      );
      supabaseReady = true;
    } catch (e) {
      debugPrint('⚠️ Supabase init failed (using placeholder .env?): $e');
    }

    // 6. Register Auth services
    if (supabaseReady) {
      setupAuthInjection();
    } else {
      _registerFallbackAuth();
    }

    // 7. Initialize Background Sync Worker
    try {
      await OfflineSyncQueueManager().initialize();
    } catch (e) {
      debugPrint('⚠️ Workmanager init failed: $e');
    }

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    return const FlowSyncApp();
  }
}

/// Registers a minimal AuthBloc when Supabase is not available
void _registerFallbackAuth() {
  // Provide a no-op AuthBloc that immediately emits Unauthenticated
  getIt.registerFactory<AuthBloc>(
    () => _FallbackAuthBloc(),
  );
}

class _FallbackAuthBloc extends AuthBloc {
  _FallbackAuthBloc() : super(_NoOpAuthRepository());
}

class _NoOpAuthRepository implements IAuthRepository {
  @override
  Future<AuthUser?> getCurrentUser() async => null;
  @override
  Future<AuthUser> signIn(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<AuthUser> signUp(String email, String password, DateTime dob) =>
      throw UnimplementedError();
  @override
  Future<void> signOut() async {}
  @override
  Future<void> sendParentConsentOtp(String phone) =>
      throw UnimplementedError();
  @override
  Future<bool> verifyParentConsentOtp(String phone, String otp) =>
      throw UnimplementedError();
  @override
  Future<String> fetchEncryptedEccKey(String argonHash) =>
      throw UnimplementedError();
}

class FlowSyncApp extends StatelessWidget {
  const FlowSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>(
          create: (_) => getIt<ThemeCubit>(),
        ),
        BlocProvider<AuthBloc>(
          create: (_) => getIt<AuthBloc>()..add(AppStarted()),
        ),
        BlocProvider<NlpInputBloc>(
          create: (_) => getIt<NlpInputBloc>(),
        ),
        BlocProvider<ScheduleBloc>(
          create: (_) => getIt<ScheduleBloc>()..add(ScheduleStarted()),
        ),
      ],
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return MaterialApp.router(
            title: 'FlowSync',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeState.themeMode,
            routerConfig: appRouter,
          );
        },
      ),
    );
  }
}
