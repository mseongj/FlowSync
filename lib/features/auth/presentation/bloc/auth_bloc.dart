import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flow_sync/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:flow_sync/features/auth/domain/entities/auth_user.dart';

// EVENTS
abstract class AuthEvent {}
class AppStarted extends AuthEvent {}
class LoginRequested extends AuthEvent {
  final String email;
  final String password;
  LoginRequested(this.email, this.password);
}
class SignupRequested extends AuthEvent {
  final String email;
  final String password;
  final DateTime dob;
  SignupRequested(this.email, this.password, this.dob);
}
class ParentNumberSubmitted extends AuthEvent {
  final String phone;
  ParentNumberSubmitted(this.phone);
}

// STATES
abstract class AuthState {}
class AuthInitial extends AuthState {}
class AuthUnauthenticated extends AuthState {}
class AuthAgeGatePending extends AuthState {
  final AuthUser pendingUser;
  AuthAgeGatePending(this.pendingUser);
}
class AuthConsentPending extends AuthState {}
class AuthFullyAuthenticated extends AuthState {
  final AuthUser user;
  AuthFullyAuthenticated(this.user);
}
class AuthError extends AuthState {
  final String message;
  AuthError(this.message);
}

// BLOC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final IAuthRepository _authRepository;

  AuthBloc(this._authRepository) : super(AuthInitial()) {
    on<AppStarted>((event, emit) async {
      try {
        final user = await _authRepository.getCurrentUser();
        if (user != null) {
          emit(AuthFullyAuthenticated(user));
        } else {
          emit(AuthUnauthenticated());
        }
      } catch (e) {
        emit(AuthUnauthenticated());
      }
    });

    on<LoginRequested>((event, emit) async {
      try {
        final user = await _authRepository.signIn(event.email, event.password);
        emit(AuthFullyAuthenticated(user));
      } catch (e) {
        emit(AuthError(e.toString()));
      }
    });

    on<SignupRequested>((event, emit) async {
      try {
        final user = await _authRepository.signUp(event.email, event.password, event.dob);
        if (user.requiresParentalConsent) {
          emit(AuthAgeGatePending(user));
        } else {
          emit(AuthFullyAuthenticated(user));
        }
      } catch (e) {
        emit(AuthError(e.toString()));
      }
    });

    on<ParentNumberSubmitted>((event, emit) async {
      try {
        await _authRepository.sendParentConsentOtp(event.phone);
        emit(AuthConsentPending());
      } catch (e) {
        emit(AuthError(e.toString()));
      }
    });
  }
}
