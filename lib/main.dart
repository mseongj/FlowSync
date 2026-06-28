import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/di/injection.dart';
import 'core/database/local_database_service.dart';
import 'core/background/sync_queue_manager.dart';
import 'core/theme/cubit/theme_cubit.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';

void main() async {
  // 1. Flutter Binding
  WidgetsFlutterBinding.ensureInitialized();

  // 2. DI Setup (Lazy init for non-critical services)
  configureDependencies();

  // 3. Eagerly init Local DB (blocks splash screen minimally)
  await getIt<LocalDatabaseService>().initialize();

  // 4. Initialize Supabase Client (uses compiled Env secrets)
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  // 5. Initialize Background Sync Worker (Lazy Singleton instantiation simulation)
  await OfflineSyncQueueManager().initialize();

  // 6. Run App
  runApp(const FlowSyncApp());
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
          create: (_) => getIt<AuthBloc>()..add(AuthCheckRequested()),
        ),
      ],
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return MaterialApp.router(
            title: 'FlowSync',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeState.themeMode, // Strict System Match enforced in Cubit
            routerConfig: appRouter,
          );
        },
      ),
    );
  }
}
