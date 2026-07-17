import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:flow_sync/features/auth/domain/entities/auth_user.dart';
import 'package:flow_sync/features/auth/domain/repositories/i_auth_repository.dart';

class AuthRepository implements IAuthRepository {
  final sb.SupabaseClient _supabase;

  AuthRepository(this._supabase);

  @override
  Future<AuthUser> signIn(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(email: email, password: password);
    if (response.user == null) throw Exception('Login failed');
    return _mapSupabaseUser(response.user!);
  }

  @override
  Future<AuthUser> signUp(String email, String password, DateTime dob) async {
    final response = await _supabase.auth.signUp(
      email: email, 
      password: password,
      data: {'dob': dob.toIso8601String()}
    );
    if (response.user == null) throw Exception('Signup failed');
    return _mapSupabaseUser(response.user!);
  }

  @override
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  @override
  Future<AuthUser?> getCurrentUser() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    return _mapSupabaseUser(user);
  }

  @override
  Future<void> sendParentConsentOtp(String phone) async {
    final response = await _supabase.functions.invoke(
      'send-parent-otp',
      body: {'phone': phone},
    );
    if (response.status != 200) throw Exception('Failed to send OTP');
  }

  @override
  Future<bool> verifyParentConsentOtp(String phone, String otp) async {
    // Mock implementation for now
    return otp == '123456'; 
  }

  @override
  Future<String> fetchEncryptedEccKey(String argonHash) async {
    final response = await _supabase.functions.invoke(
      'fetch-encrypted-ecc-key',
      body: {'hash': argonHash},
    );
    if (response.status != 200) throw Exception('Failed to fetch key. Rate limited or not found.');
    return response.data['encrypted_payload'] as String;
  }

  AuthUser _mapSupabaseUser(sb.User user) {
    final metadata = user.userMetadata ?? {};
    final dobStr = metadata['dob'] as String?;
    return AuthUser(
      id: user.id,
      email: user.email ?? '',
      dob: dobStr != null ? DateTime.parse(dobStr) : DateTime.now(),
      parentConsentVerifiedAt: metadata['parent_consent_verified_at'] != null 
          ? DateTime.parse(metadata['parent_consent_verified_at'] as String) 
          : null,
      familyId: metadata['family_id'] as String?,
    );
  }
}
