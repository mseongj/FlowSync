import 'dart:convert';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flow_sync/core/crypto/ecc_key_service.dart';
import 'package:flow_sync/core/crypto/event_crypto_service.dart';

/// Manages the end-to-end encrypted key exchange flow for family groups.
///
/// ## Flow: Family Creator (Admin)
/// 1. Generate ECC P-256 key pair → store locally
/// 2. Generate GMK (256-bit) → store locally
/// 3. Upload public key to `family_ecc_public_keys`
///
/// ## Flow: New Member (via Invite)
/// 1. Generate ECC P-256 key pair → store locally
/// 2. Upload public key to `family_ecc_public_keys`
/// 3. Wait for admin to wrap GMK with ECDH shared secret
/// 4. Download wrapped GMK → derive shared secret → unwrap → store GMK
///
/// ## Flow: Admin wraps GMK for new member
/// 1. Download new member's public key
/// 2. Derive ECDH shared secret
/// 3. Wrap GMK with shared secret (AES-GCM)
/// 4. Upload wrapped GMK to `family_key_store`
@lazySingleton
class FamilyKeyExchangeService {
  final EccKeyService _eccService;
  final EventCryptoService _cryptoService;
  final SupabaseClient _supabase;

  FamilyKeyExchangeService(
    this._eccService,
    this._cryptoService,
    this._supabase,
  );

  String get _uid => _supabase.auth.currentUser!.id;

  // ── Admin Flow: Family Creation ────────────────────────────────────────

  /// Called when a family is created. Sets up keys for the admin.
  Future<void> setupKeysForNewFamily(String familyId) async {
    // 1. Generate ECC key pair
    final publicKeyBase64 = await _eccService.generateAndStoreKeyPair();

    // 2. Ensure GMK exists
    await _cryptoService.exportGmkBase64();

    // 3. Upload public key
    await _supabase.from('family_ecc_public_keys').upsert({
      'family_id': familyId,
      'user_id': _uid,
      'public_key': publicKeyBase64,
    }, onConflict: 'family_id, user_id');
  }

  // ── New Member Flow ────────────────────────────────────────────────────

  /// Called when a new member accepts an invite. Generates keys and uploads.
  Future<void> setupKeysForNewMember(String familyId) async {
    // 1. Generate ECC key pair
    final publicKeyBase64 = await _eccService.generateAndStoreKeyPair();

    // 2. Upload public key
    await _supabase.from('family_ecc_public_keys').upsert({
      'family_id': familyId,
      'user_id': _uid,
      'public_key': publicKeyBase64,
    }, onConflict: 'family_id, user_id');
  }

  /// Attempts to download and unwrap the GMK from the admin.
  /// Returns true if successful, false if the GMK hasn't been wrapped yet.
  Future<bool> tryReceiveGmk(String familyId) async {
    // 1. Check if wrapped GMK exists for this member
    try {
      // Use edge function for rate-limited access
      final response = await _supabase.functions.invoke(
        'fetch-encrypted-ecc-key',
      );

      if (response.status != 200) return false;

      final data = response.data as Map<String, dynamic>;
      final wrappedGmkBase64 = data['encrypted_payload'] as String?;
      if (wrappedGmkBase64 == null || wrappedGmkBase64.isEmpty) return false;

      // 2. Find admin's public key
      final adminKeyRows = await _supabase
          .from('family_ecc_public_keys')
          .select('public_key, user_id')
          .eq('family_id', familyId)
          .neq('user_id', _uid)
          .limit(1);

      if (adminKeyRows.isEmpty) return false;

      final adminPublicKeyBase64 = adminKeyRows.first['public_key'] as String;

      // 3. Derive shared secret via ECDH
      final sharedSecret =
          await _eccService.deriveSharedSecret(adminPublicKeyBase64);

      // 4. Unwrap GMK
      final wrappedGmk = base64Decode(wrappedGmkBase64);
      final gmk = _eccService.unwrapGmk(wrappedGmk, sharedSecret);

      // 5. Store GMK locally
      await _cryptoService.importGmkBase64(base64Encode(gmk));

      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Admin: Wrap GMK for New Member ─────────────────────────────────────

  /// Called by admin/parent when a new member's public key is detected.
  /// Wraps the local GMK with ECDH shared secret and uploads.
  Future<void> wrapAndUploadGmkForMember(
    String familyId,
    String memberId,
    String memberPublicKeyBase64,
  ) async {
    // 1. Derive shared secret with member's public key
    final sharedSecret =
        await _eccService.deriveSharedSecret(memberPublicKeyBase64);

    // 2. Get local GMK
    final gmk = await _cryptoService.exportGmkRaw();

    // 3. Wrap GMK
    final wrappedGmk = _eccService.wrapGmk(gmk, sharedSecret);
    final wrappedGmkBase64 = base64Encode(wrappedGmk);

    // 4. Upload to family_key_store
    await _supabase.from('family_key_store').upsert({
      'family_id': familyId,
      'member_id': memberId,
      'encrypted_payload': wrappedGmkBase64,
    }, onConflict: 'family_id, member_id');
  }

  /// Checks for new members who need GMK wrapping and wraps for each.
  Future<void> wrapGmkForPendingMembers(String familyId) async {
    // Get all members' public keys
    final memberKeys = await _supabase
        .from('family_ecc_public_keys')
        .select('user_id, public_key')
        .eq('family_id', familyId)
        .neq('user_id', _uid);

    // Get existing key_store entries
    final existingWraps = await _supabase
        .from('family_key_store')
        .select('member_id')
        .eq('family_id', familyId);

    final wrappedMemberIds =
        existingWraps.map((r) => r['member_id'] as String).toSet();

    // Wrap for members who don't have a wrapped GMK yet
    for (final row in memberKeys) {
      final memberId = row['user_id'] as String;
      if (wrappedMemberIds.contains(memberId)) continue;

      await wrapAndUploadGmkForMember(
        familyId,
        memberId,
        row['public_key'] as String,
      );
    }
  }

  // ── Key Status ─────────────────────────────────────────────────────────

  /// Returns the E2EE status for display in settings.
  Future<E2eeStatus> getStatus() async {
    final hasKeys = await _eccService.hasKeyPair();
    if (!hasKeys) return E2eeStatus.noKeys;

    final gmkBase64 = await _cryptoService.exportGmkBase64();
    if (gmkBase64.isEmpty) return E2eeStatus.awaitingGmk;

    return E2eeStatus.active;
  }
}

/// E2EE activation status for UI display.
enum E2eeStatus {
  /// No ECC key pair generated yet.
  noKeys,

  /// Key pair exists but GMK not received from admin.
  awaitingGmk,

  /// Fully active — AES-256-GCM with shared GMK.
  active,
}
