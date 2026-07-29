import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flow_sync/features/family/domain/entities/family.dart';
import 'package:flow_sync/features/family/domain/repositories/i_family_repository.dart';

@LazySingleton(as: IFamilyRepository)
class FamilyRepository implements IFamilyRepository {
  final SupabaseClient _supabase;

  FamilyRepository(this._supabase);

  String get _uid => _supabase.auth.currentUser!.id;

  @override
  Future<Family> createFamily(String name) async {
    // 1. Insert family row
    final familyData = await _supabase
        .from('families')
        .insert({'name': name, 'created_by': _uid})
        .select()
        .single();

    final family = Family.fromJson(familyData);

    // 2. Insert creator as admin member
    await _supabase.from('family_members').insert({
      'family_id': family.id,
      'user_id': _uid,
      'role': 'admin',
    });

    return family;
  }

  @override
  Future<Family?> getMyFamily() async {
    // Find my membership
    final membershipRows = await _supabase
        .from('family_members')
        .select('family_id')
        .eq('user_id', _uid)
        .limit(1);

    if (membershipRows.isEmpty) return null;

    final familyId = membershipRows.first['family_id'] as String;

    final familyData = await _supabase
        .from('families')
        .select()
        .eq('id', familyId)
        .single();

    final family = Family.fromJson(familyData);
    final members = await getMembers(familyId);
    return family.copyWith(members: members);
  }

  @override
  Future<List<FamilyMember>> getMembers(String familyId) async {
    // Join family_members with auth.users email via RPC or direct query
    final rows = await _supabase
        .from('family_members')
        .select('family_id, user_id, role, joined_at')
        .eq('family_id', familyId);

    return rows.map((r) => FamilyMember.fromJson(r)).toList();
  }

  @override
  Future<FamilyInvite> createInviteLink(String familyId) async {
    final data = await _supabase
        .from('family_invites')
        .insert({
          'family_id': familyId,
          'created_by': _uid,
        })
        .select()
        .single();

    return FamilyInvite.fromJson(data);
  }

  @override
  Future<void> acceptInvite(String inviteId) async {
    // 1. Fetch and validate invite
    final inviteData = await _supabase
        .from('family_invites')
        .select()
        .eq('id', inviteId)
        .single();

    final invite = FamilyInvite.fromJson(inviteData);

    if (!invite.isValid) {
      throw Exception('초대 링크가 만료되었거나 이미 사용된 링크입니다.');
    }

    // 2. Insert member
    await _supabase.from('family_members').insert({
      'family_id': invite.familyId,
      'user_id': _uid,
      'role': 'member',
    });

    // 3. Mark invite as used
    await _supabase
        .from('family_invites')
        .update({'used_at': DateTime.now().toUtc().toIso8601String(), 'used_by': _uid})
        .eq('id', inviteId);
  }
}
