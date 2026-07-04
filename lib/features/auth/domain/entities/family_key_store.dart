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
      id: json['id'],
      familyId: json['family_id'],
      memberId: json['member_id'],
      encryptedPayload: json['encrypted_payload'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}
