import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:pointycastle/export.dart';

/// AES-256-GCM symmetric encryption service for SECRET events.
///
/// Key management:
/// - A 256-bit Group Master Key (GMK) is derived per device and stored in
///   FlutterSecureStorage under [_gmkKey].
/// - If no GMK exists (first launch), one is generated automatically.
///
/// Cipher format:
///   base64(0x02 || iv [12 bytes] || ciphertext || tag [16 bytes])
@lazySingleton
class EventCryptoService {
  static const String _gmkKey = 'flowsync_group_master_key';

  /// Version marker for AES-256-GCM
  static const int _versionGcm = 0x02;

  final FlutterSecureStorage _secureStorage;

  EventCryptoService(this._secureStorage);

  // ── Key Management ──────────────────────────────────────────────────────

  /// Returns the current Group Master Key (GMK), generating one if absent.
  Future<Uint8List> _getOrCreateGmk() async {
    final stored = await _secureStorage.read(key: _gmkKey);
    if (stored != null) {
      return base64Decode(stored);
    }
    // Generate 32 random bytes (256-bit key)
    final key = _generateRandomBytes(32);
    await _secureStorage.write(key: _gmkKey, value: base64Encode(key));
    return key;
  }

  /// Exports the GMK as a base64 string (for family key exchange).
  Future<String> exportGmkBase64() async {
    final key = await _getOrCreateGmk();
    return base64Encode(key);
  }

  /// Exports the GMK as raw bytes.
  Future<Uint8List> exportGmkRaw() async {
    return _getOrCreateGmk();
  }

  /// Imports a GMK from another device (family key exchange).
  Future<void> importGmkBase64(String base64Key) async {
    await _secureStorage.write(key: _gmkKey, value: base64Key);
  }

  // ── AES-256-GCM Encryption ─────────────────────────────────────────────

  /// Encrypts [plaintext] using AES-256-GCM.
  /// Returns: `base64(0x02 || iv [12B] || ciphertext || tag [16B])`
  Future<String> encrypt(String plaintext) async {
    final key = await _getOrCreateGmk();
    final iv = _generateRandomBytes(12);
    final plaintextBytes = utf8.encode(plaintext);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128, // 16-byte tag
          iv,
          Uint8List(0), // no AAD
        ),
      );

    final output = Uint8List(cipher.getOutputSize(plaintextBytes.length));
    var offset =
        cipher.processBytes(plaintextBytes, 0, plaintextBytes.length, output, 0);
    offset += cipher.doFinal(output, offset);
    final ciphertextAndTag = output.sublist(0, offset);

    // version || iv || ciphertext+tag
    final payload = Uint8List(1 + 12 + ciphertextAndTag.length);
    payload[0] = _versionGcm;
    payload.setRange(1, 13, iv);
    payload.setRange(13, payload.length, ciphertextAndTag);

    return base64Encode(payload);
  }

  /// Decrypts the output of [encrypt].
  Future<String> decrypt(String base64Ciphertext) async {
    final key = await _getOrCreateGmk();
    final payload = base64Decode(base64Ciphertext);

    if (payload.isEmpty) {
      throw const FormatException('Empty ciphertext.');
    }

    if (payload[0] != _versionGcm) {
      throw const FormatException(
        'Unsupported ciphertext format. '
        'Legacy CTR+HMAC data must be migrated before decryption.',
      );
    }

    return _decryptGcm(payload, key);
  }

  /// AES-256-GCM decryption
  String _decryptGcm(Uint8List payload, Uint8List key) {
    // payload: 0x02 || iv [12] || ciphertext+tag
    if (payload.length < 1 + 12 + 16) {
      throw const FormatException('Invalid GCM ciphertext: too short.');
    }

    final iv = payload.sublist(1, 13);
    final ciphertextAndTag = payload.sublist(13);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          iv,
          Uint8List(0),
        ),
      );

    final output = Uint8List(cipher.getOutputSize(ciphertextAndTag.length));
    var offset = cipher.processBytes(
        ciphertextAndTag, 0, ciphertextAndTag.length, output, 0);
    offset += cipher.doFinal(output, offset);

    return utf8.decode(output.sublist(0, offset));
  }

  // ── Encrypt / Decrypt Field Helpers ────────────────────────────────────

  /// Encrypts [value] if [condition] is true; otherwise returns [value] as-is.
  Future<String> encryptIf(String value, {required bool condition}) async {
    if (!condition || value.isEmpty) return value;
    return encrypt(value);
  }

  /// Decrypts [value] if [condition] is true; otherwise returns [value] as-is.
  Future<String> decryptIf(String value, {required bool condition}) async {
    if (!condition || value.isEmpty) return value;
    try {
      return await decrypt(value);
    } catch (_) {
      return '[복호화 불가]';
    }
  }

  // ── Internal Helpers ────────────────────────────────────────────────────

  Uint8List _generateRandomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => rng.nextInt(256)),
    );
  }
}
