import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'detected_payment.dart';

class DetectionStatus {
  const DetectionStatus({
    required this.supported,
    required this.accessEnabled,
    required this.enabled,
    required this.canNotify,
    required this.promoDismissed,
    required this.sdk,
  });

  static const unsupported = DetectionStatus(
    supported: false,
    accessEnabled: false,
    enabled: false,
    canNotify: false,
    promoDismissed: true,
    sdk: 0,
  );

  /// Only Android can read other apps' notifications.
  final bool supported;

  /// The user granted "Notification access" in Android settings.
  final bool accessEnabled;

  /// The in-app switch.
  final bool enabled;

  /// The app may show its own "choose a category" notifications.
  final bool canNotify;
  final bool promoDismissed;
  final int sdk;

  bool get isWorking => supported && accessEnabled && enabled;
}

/// Talks to the Android side (PaymentNotificationListener / MainActivity).
class DetectionService {
  DetectionService() {
    if (_supported) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'eventsAvailable') onEventsAvailable?.call();
      });
    }
  }

  static const _channel = MethodChannel('expense_tracker/upi_detection');

  /// Called when new payments were queued while the app is open.
  VoidCallback? onEventsAvailable;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<DetectionStatus> status() async {
    if (!_supported) return DetectionStatus.unsupported;
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('getStatus') ?? const {};
      return DetectionStatus(
        supported: true,
        accessEnabled: m['accessEnabled'] == true,
        enabled: m['enabled'] != false,
        canNotify: m['canNotify'] == true,
        promoDismissed: m['promoDismissed'] == true,
        sdk: (m['sdk'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException {
      return DetectionStatus.unsupported;
    } on MissingPluginException {
      return DetectionStatus.unsupported;
    }
  }

  Future<void> _call(String method, [Object? args]) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Running without the Android code (for example in tests).
    }
  }

  Future<void> openAccessSettings() => _call('openAccessSettings');
  Future<void> openAppInfo() => _call('openAppInfo');
  Future<void> requestNotificationPermission() => _call('requestNotificationPermission');
  Future<void> setEnabled(bool value) => _call('setEnabled', value);
  Future<void> setPromoDismissed(bool value) => _call('setPromoDismissed', value);
  Future<void> setCategoryHints(String json) => _call('setCategoryHints', json);

  /// Returns and clears everything the listener queued.
  Future<List<DetectedPayment>> takeEvents() async {
    if (!_supported) return const [];
    try {
      final raw = await _channel.invokeMethod<String>('takeEvents');
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in list)
          if (item is Map<String, dynamic> && item['id'] is String)
            DetectedPayment.fromJson(item),
      ];
    } on MissingPluginException {
      return const [];
    } on FormatException {
      return const [];
    }
  }

  /// Id of the payment whose notification the user tapped, if any.
  Future<String?> consumeOpenRequest() async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>('consumeOpenRequest');
    } on MissingPluginException {
      return null;
    }
  }

  /// Runs the Android parser on [text]; null if it is not a payment.
  Future<DetectedPayment?> testParse(String text) async {
    if (!_supported) return null;
    final raw = await _channel.invokeMethod<String>('testParse', text);
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return DetectedPayment.fromJson({...m, 'id': 'test'});
  }
}
