import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Something is wrong with a backup file or its password. [message] is shown
/// to the user as is.
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turns the app's data into a password-protected file and back.
///
/// File layout (plain text, three lines):
///   DRIPLESS-BACKUP 1
///   {"kdf":"pbkdf2-sha256","iterations":...,"salt":...,"nonce":...,"mac":...}
///   <base64 of the AES-256-GCM encrypted JSON>
///
/// The key is derived from the password with PBKDF2-HMAC-SHA256, so the file
/// can only be opened with the same password. Nothing about the password is
/// stored in the file.
class BackupCodec {
  BackupCodec._();

  static const String magic = 'DRIPLESS-BACKUP 1';
  static const int iterations = 120000;
  static const int minPasswordLength = 6;

  static Future<SecretKey> _key(String password, List<int> salt, int rounds) {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: rounds, bits: 256);
    return kdf.deriveKeyFromPassword(password: password, nonce: salt);
  }

  /// Encrypts [data]. Runs in a background isolate so the screen stays smooth.
  static Future<Uint8List> encode(Map<String, Object?> data, String password) {
    if (password.length < minPasswordLength) {
      throw const BackupException('Use a password of at least 6 characters.');
    }
    final json = jsonEncode(data);
    return Isolate.run(() => _encode(json, password));
  }

  static Future<Uint8List> _encode(String json, String password) async {
    final algorithm = AesGcm.with256bits();
    final salt = SecretKeyData.random(length: 16).bytes;
    final key = await _key(password, salt, iterations);
    final box = await algorithm.encrypt(utf8.encode(json), secretKey: key);
    final header = jsonEncode({
      'kdf': 'pbkdf2-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
    });
    return Uint8List.fromList(
      utf8.encode('$magic\n$header\n${base64Encode(box.cipherText)}\n'),
    );
  }

  /// Decrypts a file made by [encode]. Throws [BackupException] with a
  /// readable message for a wrong password or a file that is not a backup.
  static Future<Map<String, Object?>> decode(Uint8List bytes, String password) async {
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const BackupException('This is not a Dripless backup file.');
    }
    final lines = const LineSplitter().convert(text.trim());
    if (lines.length < 3 || lines[0].trim() != magic) {
      throw const BackupException('This is not a Dripless backup file.');
    }
    final json = await Isolate.run(() => _decode(lines[1], lines[2], password));
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const BackupException('The backup file is damaged.');
    }
    return decoded;
  }

  static Future<String> _decode(String headerLine, String body, String password) async {
    try {
      final header = jsonDecode(headerLine) as Map<String, dynamic>;
      final rounds = (header['iterations'] as num).toInt();
      final key = await _key(password, base64Decode(header['salt'] as String), rounds);
      final box = SecretBox(
        base64Decode(body.trim()),
        nonce: base64Decode(header['nonce'] as String),
        mac: Mac(base64Decode(header['mac'] as String)),
      );
      final clear = await AesGcm.with256bits().decrypt(box, secretKey: key);
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw const BackupException('Wrong password, or the file was changed.');
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException('The backup file is damaged.');
    }
  }
}
