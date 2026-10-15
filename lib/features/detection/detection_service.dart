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
    required this.smsPermission,
    this.checks = const [],
  });

  static const unsupported = DetectionStatus(
    supported: false,
    accessEnabled: false,
    enabled: false,
    canNotify: false,
    promoDismissed: true,
    sdk: 0,
    smsPermission: false,
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

  /// The app may read bank SMS directly (live and past messages).
  final bool smsPermission;

  /// What happened to the last few messages, newest first.
  final List<MessageCheck> checks;

  /// Payments are recorded when either source is allowed.
  bool get isWorking => supported && enabled && (smsPermission || accessEnabled);
}

/// One line of the "Recent message checks" list.
class MessageCheck {
  const MessageCheck({
    required this.channel,
    required this.source,
    required this.outcome,
    required this.time,
    this.amountPaise,
    this.isDebit,
    this.message,
  });

  /// "sms", "sms_notification", "app_notification" or "app".
  final String channel;

  /// Bank sender ("HDFCBK ••1234"), app name, or "Phone number".
  final String source;

  /// "recorded", "merged", "not_payment", "paused" or "not_bank".
  final String outcome;
  final DateTime time;
  final int? amountPaise;
  final bool? isDebit;

  /// Error text for "save_failed".
  final String? message;

  static List<MessageCheck> parseList(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in list)
          if (item is Map<String, dynamic>)
            MessageCheck(
              channel: item['channel'] as String? ?? '',
              source: item['source'] as String? ?? '',
              outcome: item['outcome'] as String? ?? '',
              time: DateTime.fromMillisecondsSinceEpoch((item['time'] as num?)?.toInt() ?? 0),
              amountPaise: (item['amountPaise'] as num?)?.toInt(),
              isDebit: item['isDebit'] as bool?,
              message: item['message'] as String?,
            ),
      ];
    } on FormatException {
      return const [];
    }
  }
}

/// Result of asking Android for the SMS permission.
enum SmsPermissionResult {
  granted,

  /// The user said no; the app can ask again.
  denied,

  /// Android will not show the dialog any more. The user has to allow it in
  /// App info (and on Android 15+, first "Allow restricted settings").
  blocked,
}

/// Talks to the Android side (notification listener, SMS reader, MainActivity).
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
        smsPermission: m['smsPermission'] == true,
        checks: MessageCheck.parseList(m['checkLog']),
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

  Future<SmsPermissionResult> requestSmsPermission() async {
    if (!_supported) return SmsPermissionResult.blocked;
    try {
      final answer = await _channel
          .invokeMethod<String>('requestSmsPermission')
          // If Android never answers (for example the screen was rotated
          // while asking), stop waiting; the status is re-checked on resume.
          .timeout(const Duration(minutes: 2), onTimeout: () => 'denied');
      return SmsPermissionResult.values.asNameMap()[answer] ?? SmsPermissionResult.denied;
    } on MissingPluginException {
      return SmsPermissionResult.blocked;
    } on PlatformException {
      return SmsPermissionResult.denied;
    }
  }

  /// Reads bank payment SMS from the last [days] days of the inbox.
  /// Throws [PlatformException] if the SMS permission is missing.
  Future<List<DetectedPayment>> importSmsHistory(int days) async {
    if (!_supported) return const [];
    final raw = await _channel.invokeMethod<String>('importSmsHistory', days);
    return _decode(raw);
  }

  static List<DetectedPayment> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in list)
          if (item is Map<String, dynamic> && item['id'] is String)
            DetectedPayment.fromJson(item),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Returns and clears everything the listener queued.
  Future<List<DetectedPayment>> takeEvents() async {
    if (!_supported) return const [];
    try {
      return _decode(await _channel.invokeMethod<String>('takeEvents'));
    } on MissingPluginException {
      return const [];
    }
  }

  /// Puts payments back in the queue after they could not be saved, so they
  /// are tried again next time instead of being lost.
  Future<void> requeueEvents(List<DetectedPayment> events) =>
      _call('requeueEvents', jsonEncode([for (final e in events) e.toJson()]));

  /// Adds a line to "Recent message checks" when saving into the app failed.
  Future<void> reportSaveError(String message) => _call('reportSaveError', message);

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
