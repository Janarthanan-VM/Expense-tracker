/// A payment queued by the Android notification listener.
///
/// Every item is keyed by [id]. It either describes a new payment (amount
/// and direction present) or only carries a category the user picked from
/// the notification for a payment that was already saved.
class DetectedPayment {
  const DetectedPayment({
    required this.id,
    this.amountPaise,
    this.isDebit,
    this.mode,
    this.source,
    this.app,
    this.time,
    this.payeeName,
    this.payeeVpa,
    this.upiRef,
    this.categoryId,
  });

  final String id;
  final int? amountPaise;
  final bool? isDebit;

  /// "upi", "card" or "bank".
  final String? mode;

  /// "notification" (UPI app) or "sms" (bank message).
  final String? source;

  /// "Google Pay", "PhonePe", or the bank SMS sender such as "HDFCBK".
  final String? app;
  final DateTime? time;
  final String? payeeName;
  final String? payeeVpa;
  final String? upiRef;
  final String? categoryId;

  bool get hasPayment => amountPaise != null && amountPaise! > 0 && isDebit != null;

  static String? _str(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  factory DetectedPayment.fromJson(Map<String, dynamic> j) {
    final time = (j['time'] as num?)?.toInt();
    return DetectedPayment(
      id: j['id'] as String,
      amountPaise: (j['amountPaise'] as num?)?.toInt(),
      isDebit: j['isDebit'] as bool?,
      mode: _str(j['mode']),
      source: _str(j['source']),
      app: _str(j['app']),
      time: time == null ? null : DateTime.fromMillisecondsSinceEpoch(time),
      payeeName: _str(j['payeeName']),
      payeeVpa: _str(j['payeeVpa']),
      upiRef: _str(j['upiRef']),
      categoryId: _str(j['categoryId']),
    );
  }
}
