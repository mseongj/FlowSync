import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class SecureStorageRepository {
  final FlutterSecureStorage _storage;

  SecureStorageRepository({FlutterSecureStorage? storage}) 
      : _storage = storage ?? const FlutterSecureStorage();

  static const _privateKey = 'ecc_private_key';
  static const _publicKey = 'ecc_public_key';
  static const _familyMasterKey = 'family_master_key';

  Future<void> saveEccPrivateKey(String key) async {
    await _storage.write(key: _privateKey, value: key);
  }

  Future<String?> getEccPrivateKey() async {
    return await _storage.read(key: _privateKey);
  }

  Future<void> saveEccPublicKey(String key) async {
    await _storage.write(key: _publicKey, value: key);
  }

  Future<String?> getEccPublicKey() async {
    return await _storage.read(key: _publicKey);
  }

  Future<void> saveFamilyMasterKey(String key) async {
    await _storage.write(key: _familyMasterKey, value: key);
  }

  Future<String?> getFamilyMasterKey() async {
    return await _storage.read(key: _familyMasterKey);
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
