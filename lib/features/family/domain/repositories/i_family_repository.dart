import 'package:flow_sync/features/family/domain/entities/family.dart';

abstract class IFamilyRepository {
  /// Creates a new family group with the given [name].
  /// Also inserts the creator as the 'admin' member.
  Future<Family> createFamily(String name);

  /// Returns the family the current user belongs to, or null.
  Future<Family?> getMyFamily();

  /// Returns all members of [familyId], joined with their email.
  Future<List<FamilyMember>> getMembers(String familyId);

  /// Creates a single-use invite link (TTL 24h) for [familyId].
  Future<FamilyInvite> createInviteLink(String familyId);

  /// Accepts an invite by [inviteId]:
  ///   1. Validates the invite is still valid.
  ///   2. Inserts the current user into `family_members`.
  ///   3. Marks the invite as used.
  Future<void> acceptInvite(String inviteId);

  /// Updates a member's role. Only admin/parent can do this.
  Future<void> updateMemberRole({
    required String familyId,
    required String userId,
    required String newRole,
  });
}
