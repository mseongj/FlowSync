import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flow_sync/features/auth/domain/entities/auth_user.dart';
import 'package:flow_sync/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:flow_sync/features/auth/presentation/bloc/auth_bloc.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late MockAuthRepository mockRepository;

  setUp(() {
    mockRepository = MockAuthRepository();
  });

  final adultUser = AuthUser(
    id: 'user-1',
    email: 'adult@example.com',
    dob: DateTime(2000, 1, 1), // Adult
  );

  final minorUser = AuthUser(
    id: 'user-2',
    email: 'minor@example.com',
    dob: DateTime(2016, 1, 1), // Under 14 in 2026
  );

  group('AuthBloc', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthFullyAuthenticated] when AppStarted and user exists',
      build: () {
        when(() => mockRepository.getCurrentUser())
            .thenAnswer((_) async => adultUser);
        return AuthBloc(mockRepository);
      },
      act: (bloc) => bloc.add(AppStarted()),
      expect: () => [
        isA<AuthFullyAuthenticated>()
            .having((s) => s.user.email, 'email', 'adult@example.com'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthUnauthenticated] when AppStarted and no user',
      build: () {
        when(() => mockRepository.getCurrentUser())
            .thenAnswer((_) async => null);
        return AuthBloc(mockRepository);
      },
      act: (bloc) => bloc.add(AppStarted()),
      expect: () => [isA<AuthUnauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthFullyAuthenticated] on successful LoginRequested',
      build: () {
        when(
          () => mockRepository.signIn('test@test.com', 'password123'),
        ).thenAnswer((_) async => adultUser);
        return AuthBloc(mockRepository);
      },
      act: (bloc) => bloc.add(LoginRequested('test@test.com', 'password123')),
      expect: () => [isA<AuthFullyAuthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthAgeGatePending] when minor signs up',
      build: () {
        when(
          () => mockRepository.signUp(
            'minor@test.com',
            'password123',
            minorUser.dob,
          ),
        ).thenAnswer((_) async => minorUser);
        return AuthBloc(mockRepository);
      },
      act: (bloc) => bloc.add(
        SignupRequested('minor@test.com', 'password123', minorUser.dob),
      ),
      expect: () => [
        isA<AuthAgeGatePending>().having(
          (s) => s.pendingUser.requiresParentalConsent,
          'requiresParentalConsent',
          true,
        ),
      ],
    );
  });
}
