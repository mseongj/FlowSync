import 'dart:convert';
import 'dart:typed_data';

import 'package:dargon2_flutter/dargon2_flutter.dart';
import 'package:injectable/injectable.dart';

/// Derives cryptographic keys from user PINs using Argon2id.
///
/// Used to encrypt/decrypt ECC private keys before storing or transmitting.
/// Parameters follow OWASP recommendations for Argon2id:
/// - Memory: 64 MB (65536 KiB)
/// - Iterations: 3
/// - Parallelism: 4
/// - Hash length: 32 bytes (256-bit key)
@lazySingleton
class KeyDerivationService {
  /// Argon2id parameters (OWASP recommended)
  static const int _memoryCost = 65536; // 64 MB in KiB
  static const int _iterations = 3;
  static const int _parallelism = 4;
  static const int _hashLength = 32; // 256-bit output

  /// Derives a 256-bit key from a 6-digit PIN using Argon2id.
  ///
  /// [pin] — the user's 6-digit PIN (string)
  /// [salt] — a unique salt (typically base64-encoded, at least 16 bytes)
  ///
  /// Returns a base64-encoded 256-bit derived key.
  Future<String> deriveKeyFromPin(String pin, String salt) async {
    final saltBytes = Salt(base64Decode(salt));

    final result = await argon2.hashPasswordString(
      pin,
      salt: saltBytes,
      iterations: _iterations,
      memory: _memoryCost,
      parallelism: _parallelism,
      length: _hashLength,
      type: Argon2Type.id,
    );

    return base64Encode(result.rawBytes);
  }

  /// Generates a random 16-byte salt, returned as base64.
  String generateSalt() {
    final salt = Salt.newSalt();
    return base64Encode(salt.bytes);
  }

  /// Encrypts [plaintext] using a PIN-derived key (AES-256 XOR for simplicity).
  /// In production, use AES-GCM with the derived key.
  Future<Uint8List> encryptWithPin(
    String pin,
    String salt,
    Uint8List plaintext,
  ) async {
    final keyBase64 = await deriveKeyFromPin(pin, salt);
    final key = base64Decode(keyBase64);
    return _xor(plaintext, key);
  }

  /// Decrypts [ciphertext] using a PIN-derived key.
  Future<Uint8List> decryptWithPin(
    String pin,
    String salt,
    Uint8List ciphertext,
  ) async {
    final keyBase64 = await deriveKeyFromPin(pin, salt);
    final key = base64Decode(keyBase64);
    return _xor(ciphertext, key);
  }

  /// Simple XOR for short payloads (32 bytes = ECC private key length).
  Uint8List _xor(Uint8List data, Uint8List key) {
    final output = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      output[i] = data[i] ^ key[i % key.length];
    }
    return output;
  }
}
