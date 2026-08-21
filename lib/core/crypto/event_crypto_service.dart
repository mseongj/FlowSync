import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as legacy_crypto;
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
/// Cipher format (v2):
///   base64(0x02 || iv [12 bytes] || ciphertext || tag [16 bytes])
///
/// Legacy format (v1, read-only for migration):
///   base64(iv [16 bytes] || ciphertext || hmac [32 bytes])
@lazySingleton
class EventCryptoService {
  static const String _gmkKey = 'flowsync_group_master_key';

  /// Version markers
  static const int _versionGcm = 0x02;
  static const int _versionLegacyCtr = 0x01;

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

  /// Decrypts the output of [encrypt]. Supports both v2 (GCM) and v1 (legacy CTR+HMAC).
  Future<String> decrypt(String base64Ciphertext) async {
    final key = await _getOrCreateGmk();
    final payload = base64Decode(base64Ciphertext);

    if (payload.isEmpty) {
      throw const FormatException('Empty ciphertext.');
    }

    // Check version byte
    if (payload[0] == _versionGcm) {
      return _decryptGcm(payload, key);
    } else {
      // Legacy v1 (no version byte — first byte is part of IV)
      return _decryptLegacyCtr(payload, key);
    }
  }

  /// AES-256-GCM decryption (v2 format)
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

  /// Legacy AES-CTR+HMAC decryption (v1 format, for migration only)
  String _decryptLegacyCtr(Uint8List payload, Uint8List key) {
    if (payload.length < 16 + 32) {
      throw const FormatException('Invalid legacy ciphertext: too short.');
    }

    final iv = payload.sublist(0, 16);
    final ciphertext = payload.sublist(16, payload.length - 32);
    final storedMac = payload.sublist(payload.length - 32);
    final computedMac = _computeLegacyHmac(key, iv, ciphertext);

    if (!_safeEquals(storedMac, computedMac)) {
      throw const FormatException('MAC verification failed: data corrupted.');
    }

    final plaintext = _legacyAesCtrXor(ciphertext, key, iv);
    return utf8.decode(plaintext);
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

  // ── Migration ──────────────────────────────────────────────────────────

  /// Re-encrypts a legacy CTR+HMAC ciphertext to AES-GCM format.
  /// Returns null if the input is already GCM or decryption fails.
  Future<String?> migrateToGcm(String base64Ciphertext) async {
    final payload = base64Decode(base64Ciphertext);
    if (payload.isEmpty) return null;

    // Already GCM?
    if (payload[0] == _versionGcm) return null;

    try {
      final plaintext = await decrypt(base64Ciphertext);
      return encrypt(plaintext);
    } catch (_) {
      return null;
    }
  }

  /// Checks if a ciphertext is in legacy CTR+HMAC format.
  bool isLegacyFormat(String base64Ciphertext) {
    try {
      final payload = base64Decode(base64Ciphertext);
      return payload.isNotEmpty && payload[0] != _versionGcm;
    } catch (_) {
      return false;
    }
  }

  // ── Legacy Helpers (kept for backward compatibility) ────────────────────

  Uint8List _legacyAesCtrXor(Uint8List data, Uint8List key, Uint8List iv) {
    final output = Uint8List(data.length);
    var blockIndex = 0;
    const blockSize = 32;
    Uint8List? keystream;
    var ksOffset = blockSize;

    for (var i = 0; i < data.length; i++) {
      if (ksOffset >= blockSize) {
        final counterBytes = ByteData(4)..setUint32(0, blockIndex, Endian.big);
        final input = Uint8List.fromList([
          ...key,
          ...iv,
          ...counterBytes.buffer.asUint8List(),
        ]);
        keystream =
            Uint8List.fromList(legacy_crypto.sha256.convert(input).bytes);
        blockIndex++;
        ksOffset = 0;
      }
      output[i] = data[i] ^ keystream![ksOffset++];
    }

    return output;
  }

  Uint8List _computeLegacyHmac(
    Uint8List key,
    Uint8List iv,
    Uint8List ciphertext,
  ) {
    final hmacSha256 = legacy_crypto.Hmac(legacy_crypto.sha256, key);
    final message = Uint8List.fromList([...iv, ...ciphertext]);
    return Uint8List.fromList(hmacSha256.convert(message).bytes);
  }

  // ── Internal Helpers ────────────────────────────────────────────────────

  bool _safeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  Uint8List _generateRandomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => rng.nextInt(256)),
    );
  }
}
