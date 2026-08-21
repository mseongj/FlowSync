import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:pointycastle/export.dart';

import 'package:flow_sync/features/auth/data/crypto/secure_storage_repository.dart';

/// ECC P-256 key pair service for ECDH key exchange.
///
/// Generates NIST P-256 (secp256r1) key pairs, stores them in
/// [SecureStorageRepository], and derives shared secrets via ECDH.
@lazySingleton
class EccKeyService {
  final SecureStorageRepository _storage;

  EccKeyService(this._storage);

  static final ECDomainParameters _domainParams =
      ECDomainParameters('prime256v1');

  // ── Key Generation ──────────────────────────────────────────────────────

  /// Generates a new ECC P-256 key pair and stores both keys in SecureStorage.
  /// Returns the public key as a base64-encoded uncompressed point.
  Future<String> generateAndStoreKeyPair() async {
    final keyGen = ECKeyGenerator()
      ..init(ParametersWithRandom(
        ECKeyGeneratorParameters(_domainParams),
        _secureRandom(),
      ));

    final pair = keyGen.generateKeyPair();
    final privateKey = pair.privateKey as ECPrivateKey;
    final publicKey = pair.publicKey as ECPublicKey;

    // Serialize and store
    final privateKeyBase64 = base64Encode(
      _bigIntToBytes(privateKey.d!, 32),
    );
    final publicKeyBase64 = base64Encode(
      publicKey.Q!.getEncoded(false),
    );

    await _storage.saveEccPrivateKey(privateKeyBase64);
    await _storage.saveEccPublicKey(publicKeyBase64);

    return publicKeyBase64;
  }

  /// Returns the stored public key as base64, or null if not generated yet.
  Future<String?> getPublicKeyBase64() async {
    return _storage.getEccPublicKey();
  }

  /// Returns true if an ECC key pair exists in SecureStorage.
  Future<bool> hasKeyPair() async {
    final pk = await _storage.getEccPrivateKey();
    return pk != null;
  }

  // ── ECDH Key Exchange ───────────────────────────────────────────────────

  /// Derives a 256-bit shared secret using ECDH with:
  /// - The local private key from SecureStorage
  /// - The other party's public key (base64 uncompressed point)
  ///
  /// The raw ECDH output (x-coordinate) is hashed with SHA-256 to produce
  /// a uniform 256-bit key suitable for AES-256-GCM.
  Future<Uint8List> deriveSharedSecret(String otherPublicKeyBase64) async {
    final privateKeyBase64 = await _storage.getEccPrivateKey();
    if (privateKeyBase64 == null) {
      throw StateError('ECC private key not found. Generate a key pair first.');
    }

    final privateKeyBytes = base64Decode(privateKeyBase64);
    final privateKeyD = _bytesToBigInt(privateKeyBytes);
    final ecPrivateKey = ECPrivateKey(privateKeyD, _domainParams);

    final otherPublicKeyBytes = base64Decode(otherPublicKeyBase64);
    final otherPublicPoint =
        _domainParams.curve.decodePoint(otherPublicKeyBytes);
    final ecPublicKey = ECPublicKey(otherPublicPoint, _domainParams);

    // ECDH: multiply other's public point by our private scalar
    final sharedPoint = ecPublicKey.Q! * ecPrivateKey.d;
    final sharedX = sharedPoint!.x!.toBigInteger()!;
    final sharedXBytes = _bigIntToBytes(sharedX, 32);

    // Hash the x-coordinate with SHA-256 for key uniformity (NIST SP 800-56C)
    final digest = SHA256Digest();
    final hash = Uint8List(digest.digestSize);
    digest.update(sharedXBytes, 0, sharedXBytes.length);
    digest.doFinal(hash, 0);

    return hash;
  }

  // ── GMK Wrapping (AES-GCM) ─────────────────────────────────────────────

  /// Wraps (encrypts) a GMK with a shared secret using AES-256-GCM.
  /// Returns base64(iv [12 bytes] || ciphertext || tag [16 bytes]).
  Uint8List wrapGmk(Uint8List gmk, Uint8List sharedSecret) {
    final iv = _generateRandomBytes(12);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true, // encrypt
        AEADParameters(
          KeyParameter(sharedSecret),
          128, // tag length in bits
          iv,
          Uint8List(0), // no AAD
        ),
      );

    final output = Uint8List(cipher.getOutputSize(gmk.length));
    final len = cipher.processBytes(gmk, 0, gmk.length, output, 0);
    cipher.doFinal(output, len);

    // iv || ciphertext+tag
    final result = Uint8List(12 + output.length);
    result.setRange(0, 12, iv);
    result.setRange(12, result.length, output);

    return result;
  }

  /// Unwraps (decrypts) a GMK from a wrapped payload using shared secret.
  Uint8List unwrapGmk(Uint8List wrappedPayload, Uint8List sharedSecret) {
    final iv = wrappedPayload.sublist(0, 12);
    final ciphertextAndTag = wrappedPayload.sublist(12);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false, // decrypt
        AEADParameters(
          KeyParameter(sharedSecret),
          128, // tag length in bits
          iv,
          Uint8List(0), // no AAD
        ),
      );

    final output = Uint8List(cipher.getOutputSize(ciphertextAndTag.length));
    final len = cipher.processBytes(
        ciphertextAndTag, 0, ciphertextAndTag.length, output, 0);
    cipher.doFinal(output, len);

    return output.sublist(0, len + cipher.doFinal(output, len));
  }

  // ── Internal Helpers ────────────────────────────────────────────────────

  SecureRandom _secureRandom() {
    final secureRandom = FortunaRandom();
    final seedSource = Random.secure();
    final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  Uint8List _generateRandomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => rng.nextInt(256)),
    );
  }

  /// Converts a BigInt to a fixed-length byte array (big-endian).
  static Uint8List _bigIntToBytes(BigInt number, int byteLength) {
    final result = Uint8List(byteLength);
    var n = number;
    for (var i = byteLength - 1; i >= 0; i--) {
      result[i] = (n & BigInt.from(0xFF)).toInt();
      n = n >> 8;
    }
    return result;
  }

  /// Converts a byte array to BigInt (big-endian).
  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (var i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }
}
