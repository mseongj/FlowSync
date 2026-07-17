import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../di/injection.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';

import '../../features/auth/presentation/screens/auth_screen.dart';
import '../../features/schedule/presentation/screens/dashboard_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  redirect: (context, state) {
    final authState = getIt<AuthBloc>().state;
    final isGoingToLogin = state.matchedLocation == '/login';

    if (authState is AuthUnauthenticated && !isGoingToLogin) {
      return '/login';
    }
    if (authState is AuthFullyAuthenticated && isGoingToLogin) {
      return '/dashboard';
    }
    if (authState is AuthFullyAuthenticated && state.matchedLocation == '/') {
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
