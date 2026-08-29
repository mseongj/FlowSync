import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dargon2_flutter/dargon2_flutter.dart';
import 'package:injectable/injectable.dart';
import 'package:pointycastle/export.dart';

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

  /// Encrypts [plaintext] using a PIN-derived key with AES-256-GCM.
  ///
  /// Output format: `iv [12 bytes] || ciphertext || tag [16 bytes]`
  /// The 16-byte authentication tag ensures any tampering is detected.
  Future<Uint8List> encryptWithPin(
    String pin,
    String salt,
    Uint8List plaintext,
  ) async {
    final keyBase64 = await deriveKeyFromPin(pin, salt);
    final key = base64Decode(keyBase64);
    final iv = _generateRandomBytes(12);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(Uint8List.fromList(key)),
          128, // 16-byte tag
          iv,
          Uint8List(0),
        ),
      );

    final output = Uint8List(cipher.getOutputSize(plaintext.length));
    var offset = cipher.processBytes(plaintext, 0, plaintext.length, output, 0);
    offset += cipher.doFinal(output, offset);
    final ciphertextAndTag = output.sublist(0, offset);

    // iv || ciphertext+tag
    final result = Uint8List(12 + ciphertextAndTag.length);
    result.setRange(0, 12, iv);
    result.setRange(12, result.length, ciphertextAndTag);
    return result;
  }

  /// Decrypts [ciphertext] using a PIN-derived key with AES-256-GCM.
  ///
  /// Throws [InvalidCipherTextException] if the PIN is wrong or data is tampered.
  Future<Uint8List> decryptWithPin(
    String pin,
    String salt,
    Uint8List ciphertext,
  ) async {
    if (ciphertext.length < 12 + 16) {
      throw const FormatException('Ciphertext too short for AES-GCM.');
    }

    final keyBase64 = await deriveKeyFromPin(pin, salt);
    final key = base64Decode(keyBase64);
    final iv = ciphertext.sublist(0, 12);
    final ciphertextAndTag = ciphertext.sublist(12);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(Uint8List.fromList(key)),
          128,
          iv,
          Uint8List(0),
        ),
      );

    final output = Uint8List(cipher.getOutputSize(ciphertextAndTag.length));
    var offset = cipher.processBytes(
        ciphertextAndTag, 0, ciphertextAndTag.length, output, 0);
    offset += cipher.doFinal(output, offset);
    return output.sublist(0, offset);
  }

  Uint8List _generateRandomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => rng.nextInt(256)),
    );
  }
}
