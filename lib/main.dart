import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import 'package:flow_sync/core/config/env.dart';
import 'package:flow_sync/core/di/injection.dart';
import 'package:flow_sync/core/di/auth_injection.dart';
import 'package:flow_sync/core/database/local_database_service.dart';
import 'package:flow_sync/core/background/sync_queue_manager.dart';
import 'package:flow_sync/core/theme/cubit/theme_cubit.dart';
import 'package:flow_sync/core/theme/app_theme.dart';
import 'package:flow_sync/core/router/app_router.dart';
import 'package:flow_sync/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:flow_sync/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:flow_sync/features/auth/domain/entities/auth_user.dart';
import 'package:flow_sync/features/family/presentation/bloc/family_bloc.dart';
import 'package:flow_sync/features/auth/presentation/widgets/app_lifecycle_observer.dart';
import 'package:flow_sync/features/family/presentation/widgets/deep_link_handler.dart';
import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_bloc.dart';
import 'package:flow_sync/features/schedule/presentation/bloc/schedule_bloc.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppInitializer());
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isInitialized = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await initializeDateFormatting('ko', null);

      // 1. DI Setup (injectable-generated registrations)
      configureDependencies();

      // 2. Local DB (Hive)
      await getIt<LocalDatabaseService>().initialize();

      // 3. Supabase
      var supabaseReady = false;
      try {
        await Supabase.initialize(
          url: Env.supabaseUrl,
          publishableKey: Env.supabaseAnonKey,
        );
        supabaseReady = true;
        // Register SupabaseClient manually AFTER successful init
        getIt.registerLazySingleton<SupabaseClient>(
          () => Supabase.instance.client,
        );
      } catch (e) {
        debugPrint('⚠️ Supabase init failed: $e');
      }

      // 4. Auth services
      if (supabaseReady) {
        setupAuthInjection();
      } else {
        _registerFallbackAuth();
      }

      // 5. Background Sync Worker
      try {
        await getIt<OfflineSyncQueueManager>().initialize();
      } catch (e) {
        debugPrint('⚠️ Workmanager init failed: $e');
      }
    } catch (e, st) {
      debugPrint('🚨 CRITICAL INIT ERROR: $e');
      debugPrint('🚨 StackTrace: $st');
      _initError = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_initError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Initialization failed:\n$_initError',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return const FlowSyncApp();
  }
}

/// Registers a minimal AuthBloc when Supabase is not available
void _registerFallbackAuth() {
  getIt.registerLazySingleton<AuthBloc>(
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
    // Build the list of providers dynamically based on what's available
    final providers = <BlocProvider>[
      BlocProvider<ThemeCubit>(
        create: (_) => getIt<ThemeCubit>(),
      ),
      BlocProvider<AuthBloc>(
        lazy: false,
        create: (_) => getIt<AuthBloc>()..add(AppStarted()),
      ),
      BlocProvider<ScheduleBloc>(
        create: (_) => getIt<ScheduleBloc>()..add(ScheduleStarted()),
      ),
    ];

    // NlpInputBloc depends on SupabaseClient via AiOrchestrationService.
    // Only provide it if SupabaseClient is registered.
    if (getIt.isRegistered<SupabaseClient>()) {
      providers.add(
        BlocProvider<NlpInputBloc>(
          create: (_) => getIt<NlpInputBloc>(),
        ),
      );
      providers.add(
        BlocProvider<FamilyBloc>(
          create: (_) => getIt<FamilyBloc>(),
        ),
      );
    }

    return MultiBlocProvider(
      providers: providers,
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return AppLifecycleObserver(
            child: DeepLinkHandler(
              child: MaterialApp.router(
                title: 'FlowSync',
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeState.themeMode,
                routerConfig: appRouter,
              ),
            ),
          );
        },
      ),
    );
  }
}

