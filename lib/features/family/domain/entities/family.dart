/// Represents a family group.
class Family {
  final String id;
  final String name;
  final String createdBy;
  final DateTime createdAt;
  final List<FamilyMember> members;

  const Family({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    this.members = const [],
  });

  factory Family.fromJson(Map<String, dynamic> json) {
    return Family(
      id: json['id'] as String,
      name: json['name'] as String,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Family copyWith({List<FamilyMember>? members}) {
    return Family(
      id: id,
      name: name,
      createdBy: createdBy,
      createdAt: createdAt,
      members: members ?? this.members,
    );
  }
}

/// Represents a member inside a family.
class FamilyMember {
  final String familyId;
  final String userId;
  final String email;
  final String role; // 'admin' | 'member'
  final DateTime joinedAt;

  const FamilyMember({
    required this.familyId,
    required this.userId,
    required this.email,
    required this.role,
    required this.joinedAt,
  });

  bool get isAdmin => role == 'admin';

  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    return FamilyMember(
      familyId: json['family_id'] as String,
      userId: json['user_id'] as String,
      email: (json['email'] as String?) ?? '',
      role: (json['role'] as String?) ?? 'member',
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }
}

/// Represents a single-use invite link payload.
class FamilyInvite {
  final String id;
  final String familyId;
  final String createdBy;
  final DateTime expiresAt;
  final DateTime? usedAt;

  const FamilyInvite({
    required this.id,
    required this.familyId,
    required this.createdBy,
    required this.expiresAt,
    this.usedAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isUsed => usedAt != null;
  bool get isValid => !isExpired && !isUsed;

  /// The deep link URI the user shares (internal scheme).
  String get deepLinkUri =>
      'flowsync://invite?id=$id&family_id=$familyId';

  factory FamilyInvite.fromJson(Map<String, dynamic> json) {
    return FamilyInvite(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      createdBy: json['created_by'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      usedAt: json['used_at'] == null
          ? null
          : DateTime.parse(json['used_at'] as String),
    );
  }
}
