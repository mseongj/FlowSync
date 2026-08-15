import 'package:flutter/widgets.dart';

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
  final String role; // 'admin' | 'parent' | 'member' | 'teenager' | 'grandparent'
  final DateTime joinedAt;

  const FamilyMember({
    required this.familyId,
    required this.userId,
    required this.email,
    required this.role,
    required this.joinedAt,
  });

  bool get isAdmin => role == FamilyRole.admin;
  bool get isParent => role == FamilyRole.parent;
  bool get isGrandparent => role == FamilyRole.grandparent;
  bool get isTeenager => role == FamilyRole.teenager;

  /// Grandparents are read-only — they can view but not edit events.
  bool get isReadOnly => role == FamilyRole.grandparent;

  /// Whether this member can manage other members' roles.
  bool get canManageRoles => isAdmin || isParent;

  String get roleLabel => FamilyRole.label(role);
  IconData get roleIcon => FamilyRole.icon(role);

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

/// Available family roles with display metadata.
class FamilyRole {
  static const admin = 'admin';
  static const parent = 'parent';
  static const member = 'member';
  static const teenager = 'teenager';
  static const grandparent = 'grandparent';

  /// All assignable roles (admin excluded — only the creator is admin).
  static const List<String> assignableRoles = [
    parent,
    member,
    teenager,
    grandparent,
  ];

  static String label(String role) {
    switch (role) {
      case admin:
        return '관리자';
      case parent:
        return '부모';
      case member:
        return '멤버';
      case teenager:
        return '청소년';
      case grandparent:
        return '조부모 (읽기전용)';
      default:
        return role;
    }
  }

  static IconData icon(String role) {
    switch (role) {
      case admin:
        return IconData(0xe7ef, fontFamily: 'MaterialIcons'); // admin_panel_settings
      case parent:
        return IconData(0xe491, fontFamily: 'MaterialIcons'); // person
      case teenager:
        return IconData(0xe559, fontFamily: 'MaterialIcons'); // school
      case grandparent:
        return IconData(0xe86a, fontFamily: 'MaterialIcons'); // elderly
      default:
        return IconData(0xe491, fontFamily: 'MaterialIcons'); // person
    }
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
