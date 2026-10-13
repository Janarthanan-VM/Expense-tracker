import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Creates and keeps the database encryption key in Android Keystore-backed
/// secure storage. The key never leaves the device.
///
/// If the app is uninstalled or its data is cleared, this key is lost and the
/// old database file cannot be opened. The app's own encrypted backup file
/// (added in the backup step) is what protects the user's data.
class DbKeyStore {
  DbKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const String _keyName = 'db_encryption_key_v1';

  Future<String> getOrCreateKey() async {
    final existing = await _storage.read(key: _keyName);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = base64UrlEncode(bytes);
    await _storage.write(key: _keyName, value: key);
    return key;
  }
}
