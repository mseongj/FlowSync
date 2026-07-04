class AuthUser {
  final String id;
  final String email;
  final DateTime dob;
  final DateTime? parentConsentVerifiedAt;
  final String? familyId;

  const AuthUser({
    required this.id,
    required this.email,
    required this.dob,
    this.parentConsentVerifiedAt,
    this.familyId,
  });

  bool get isUnder14 {
    final today = DateTime.now();
    final age = today.year - dob.year;
    if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) {
      return age - 1 < 14;
    }
    return age < 14;
  }

  bool get requiresParentalConsent => isUnder14 && parentConsentVerifiedAt == null;
}
