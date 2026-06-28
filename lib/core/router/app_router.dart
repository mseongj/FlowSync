import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../di/injection.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  redirect: (context, state) {
    // We will wire up actual auth state later. For Unit 2, we just demonstrate structure.
    final authState = getIt<AuthBloc>().state;
    final isGoingToLogin = state.matchedLocation == '/login';

    if (authState is AuthUnauthenticated && !isGoingToLogin) {
      return '/login';
    }
    if (authState is AuthAuthenticated && isGoingToLogin) {
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
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('Login Screen (Unit 3)')),
      ),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('Dashboard Screen (Unit 5)')),
      ),
    ),
  ],
);
