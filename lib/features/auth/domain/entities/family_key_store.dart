class FamilyKeyStore {
  final String id;
  final String familyId;
  final String memberId;
  final String encryptedPayload; // Argon2-encrypted ECC Private Key + Public Key + Family Master Key
  final DateTime createdAt;
  final DateTime updatedAt;

  const FamilyKeyStore({
    required this.id,
    required this.familyId,
    required this.memberId,
    required this.encryptedPayload,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FamilyKeyStore.fromJson(Map<String, dynamic> json) {
    return FamilyKeyStore(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      memberId: json['member_id'] as String,
      encryptedPayload: json['encrypted_payload'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
