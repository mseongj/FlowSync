import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_sync/core/di/injection.dart';
import 'package:flow_sync/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:flow_sync/features/auth/presentation/screens/auth_screen.dart';
import 'package:flow_sync/features/schedule/presentation/screens/dashboard_screen.dart';

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
        builder: (context, state) => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
    ],
  );
}
