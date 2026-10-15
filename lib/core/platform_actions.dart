import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android screens the app opens and waits for: the file picker, Google's QR
/// scanner and the user's UPI app. Implemented in MainActivity.kt.
class PlatformActions {
  const PlatformActions();

  static const _channel = MethodChannel('expense_tracker/upi_detection');

  bool get supported => !kIsWeb && Platform.isAndroid;

  /// Asks where to save [bytes]. Returns false if the user cancelled.
  Future<bool> saveDocument({
    required String name,
    required String mime,
    required Uint8List bytes,
  }) async {
    if (!supported) return false;
    final ok = await _channel.invokeMethod<bool>(
      'saveDocument',
      {'name': name, 'mime': mime, 'bytes': bytes},
    );
    return ok ?? false;
  }

  /// Asks for a file and returns its contents, or null if cancelled.
  Future<Uint8List?> openDocument() async {
    if (!supported) return null;
    return _channel.invokeMethod<Uint8List>('openDocument');
  }

  /// Scans a QR code. Returns its text, or null if the user backed out.
  Future<String?> scanQr() async {
    if (!supported) return null;
    return _channel.invokeMethod<String>('scanQr');
  }

  /// Opens a UPI app for [upiLink]. Returns the UPI app's response text,
  /// which may be null when the app sends nothing back.
  Future<({int resultCode, String? response})> payUpi(String upiLink) async {
    final m = await _channel.invokeMapMethod<String, Object?>('payUpi', upiLink) ?? const {};
    return (
      resultCode: (m['resultCode'] as num?)?.toInt() ?? 0,
      response: m['response'] as String?,
    );
  }
}
