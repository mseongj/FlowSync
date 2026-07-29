import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

/// AES-256-GCM symmetric encryption service for SECRET events.
///
/// Key management:
/// - A 256-bit Group Master Key (GMK) is derived per device and stored in
///   FlutterSecureStorage under [_gmkKey].
/// - If no GMK exists (first launch), one is generated automatically.
///
/// Implementation note:
/// - `dart:crypto` does not provide AES-GCM natively.
/// - We use AES-CTR emulation via SHA-256 keystream XOR for
///   confidentiality + HMAC-SHA256 for integrity (Encrypt-then-MAC).
/// - This is a pragmatic solution until the `cryptography` package is
///   integrated in Phase 2 (ECC keypair + true AES-GCM via pointycastle).
@lazySingleton
class EventCryptoService {
  static const String _gmkKey = 'flowsync_group_master_key';

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

  /// Exports the GMK as a base64 string (for family key exchange in Phase 2).
  Future<String> exportGmkBase64() async {
    final key = await _getOrCreateGmk();
    return base64Encode(key);
  }

  /// Imports a GMK from another device (family key exchange).
  Future<void> importGmkBase64(String base64Key) async {
    await _secureStorage.write(key: _gmkKey, value: base64Key);
  }

  // ── Encryption ──────────────────────────────────────────────────────────

  /// Encrypts [plaintext] and returns a single base64 string:
  /// `base64(iv [16 bytes] || ciphertext || hmac [32 bytes])`
  Future<String> encrypt(String plaintext) async {
    final key = await _getOrCreateGmk();
    final iv = _generateRandomBytes(16);
    final plaintextBytes = utf8.encode(plaintext);

    final ciphertext = _aesCtrXor(plaintextBytes, key, iv);
    final mac = _computeHmac(key, iv, ciphertext);

    final payload = Uint8List(16 + ciphertext.length + 32);
    payload.setRange(0, 16, iv);
    payload.setRange(16, 16 + ciphertext.length, ciphertext);
    payload.setRange(16 + ciphertext.length, payload.length, mac);

    return base64Encode(payload);
  }

  /// Decrypts the output of [encrypt]. Throws if the MAC is invalid.
  Future<String> decrypt(String base64Ciphertext) async {
    final key = await _getOrCreateGmk();
    final payload = base64Decode(base64Ciphertext);

    if (payload.length < 16 + 32) {
      throw const FormatException('Invalid ciphertext: too short.');
    }

    final iv = payload.sublist(0, 16);
    final ciphertext = payload.sublist(16, payload.length - 32);
    final storedMac = payload.sublist(payload.length - 32);
    final computedMac = _computeHmac(key, iv, ciphertext);

    // Constant-time comparison
    if (!_safeEquals(storedMac, computedMac)) {
      throw const FormatException('MAC verification failed: data corrupted.');
    }

    final plaintext = _aesCtrXor(ciphertext, key, iv);
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
      // If decryption fails (e.g. key mismatch), return a placeholder
      return '[복호화 불가]';
    }
  }

  // ── Internal Helpers ────────────────────────────────────────────────────

  /// AES-CTR keystream via SHA-256 (pseudo-AES for confidentiality).
  Uint8List _aesCtrXor(Uint8List data, Uint8List key, Uint8List iv) {
    final output = Uint8List(data.length);
    var blockIndex = 0;
    final blockSize = 32; // SHA-256 output
    Uint8List? keystream;
    var ksOffset = blockSize; // Force first block generation

    for (var i = 0; i < data.length; i++) {
      if (ksOffset >= blockSize) {
        // Generate next keystream block: SHA-256(key || iv || blockIndex)
        final counterBytes = ByteData(4)..setUint32(0, blockIndex, Endian.big);
        final input = Uint8List.fromList([
          ...key,
          ...iv,
          ...counterBytes.buffer.asUint8List(),
        ]);
        keystream = Uint8List.fromList(sha256.convert(input).bytes);
        blockIndex++;
        ksOffset = 0;
      }
      output[i] = data[i] ^ keystream![ksOffset++];
    }

    return output;
  }

  Uint8List _computeHmac(
    Uint8List key,
    Uint8List iv,
    Uint8List ciphertext,
  ) {
    final hmacSha256 = Hmac(sha256, key);
    final message = Uint8List.fromList([...iv, ...ciphertext]);
    return Uint8List.fromList(hmacSha256.convert(message).bytes);
  }

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
