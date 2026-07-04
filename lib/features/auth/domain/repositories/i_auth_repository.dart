import 'package:flow_sync/features/auth/domain/entities/auth_user.dart';

abstract class IAuthRepository {
  /// Signs in a user with email and password
  Future<AuthUser> signIn(String email, String password);

  /// Signs up a user. Requires DOB for age gate.
  Future<AuthUser> signUp(String email, String password, DateTime dob);

  /// Logs out the current user
  Future<void> signOut();

  /// Gets the currently authenticated user (returns null if not authenticated)
  Future<AuthUser?> getCurrentUser();

  /// Invokes Edge Function to send OTP to parent's phone
  Future<void> sendParentConsentOtp(String phone);

  /// Verifies the OTP sent to parent
  Future<bool> verifyParentConsentOtp(String phone, String otp);
  
  /// Invokes rate-limited Edge Function to fetch encrypted ECC keys using Argon hash
  Future<String> fetchEncryptedEccKey(String argonHash);
}
