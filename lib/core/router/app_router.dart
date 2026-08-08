import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_sync/core/di/injection.dart';
import 'package:flow_sync/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:flow_sync/features/auth/presentation/screens/auth_screen.dart';
import 'package:flow_sync/features/auth/presentation/screens/splash_screen.dart';
import 'package:flow_sync/features/family/presentation/screens/family_screen.dart';
import 'package:flow_sync/features/nlp/domain/entities/ai_scheduling_response.dart';
import 'package:flow_sync/features/schedule/presentation/screens/dashboard_screen.dart';
import 'package:flow_sync/features/schedule/presentation/screens/manual_event_form_screen.dart';
import 'package:flow_sync/features/settings/presentation/screens/settings_screen.dart';

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
      (dynamic _) => notifyListeners(),
    );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

GoRouter? _routerInstance;

/// Creates the router lazily — only call AFTER DI is fully configured
/// (i.e. after AuthBloc has been registered in GetIt).
GoRouter get appRouter {
  return _routerInstance ??= _createRouter();
}

GoRouter _createRouter() {
  final authBloc = getIt<AuthBloc>();
  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    redirect: (context, state) {
      final authState = authBloc.state;
      final isGoingToLogin = state.matchedLocation == '/login';

      if (authState is AuthUnauthenticated && !isGoingToLogin) {
        return '/login';
      }
      if (authState is AuthFullyAuthenticated && isGoingToLogin) {
        return '/dashboard';
      }
      if (authState is AuthFullyAuthenticated &&
          state.matchedLocation == '/') {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/event/new',
        builder: (context, state) => const ManualEventFormScreen(),
      ),
      GoRoute(
        path: '/event/edit',
        builder: (context, state) => ManualEventFormScreen(
          prefill: state.extra as AiSchedulingResponse?,
        ),
      ),
      GoRoute(
        path: '/family',
        builder: (context, state) => const FamilyScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
