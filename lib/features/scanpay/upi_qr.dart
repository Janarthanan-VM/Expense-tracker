/// What a UPI QR code contains: upi://pay?pa=shop@okaxis&pn=Sri%20Stores&am=250&mc=5411
class UpiQr {
  const UpiQr({
    required this.vpa,
    required this.raw,
    this.name,
    this.amountPaise,
    this.note,
    this.mcc,
  });

  /// Payee UPI ID ("pa").
  final String vpa;

  /// Payee name ("pn").
  final String? name;

  /// Fixed amount from the QR ("am"). When present it must not be changed.
  final int? amountPaise;

  /// Note ("tn").
  final String? note;

  /// Merchant category code ("mc"), used to suggest a category.
  final String? mcc;

  /// The QR text as scanned.
  final String raw;

  /// Parses a scanned QR. Returns null if it is not a UPI payment QR.
  static UpiQr? parse(String? text) {
    if (text == null) return null;
    final trimmed = text.trim();
    if (!trimmed.toLowerCase().startsWith('upi://pay')) return null;
    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } on FormatException {
      return null;
    }
    final Map<String, String> q;
    try {
      // Keys are matched without regard to case ("PA", "pa").
      q = {for (final e in uri.queryParameters.entries) e.key.toLowerCase(): e.value.trim()};
    } on ArgumentError {
      return null;
    }
    final vpa = q['pa'];
    if (vpa == null || !RegExp(r'^[\w.\-]{2,}@[a-zA-Z][\w]{1,}$').hasMatch(vpa)) return null;

    int? amount;
    final am = q['am'];
    if (am != null && am.isNotEmpty) {
      final value = double.tryParse(am);
      if (value != null && value > 0) amount = (value * 100).round();
    }
    String? clean(String? v) => (v == null || v.isEmpty) ? null : v;
    return UpiQr(
      vpa: vpa.toLowerCase(),
      name: clean(q['pn']),
      amountPaise: amount,
      note: clean(q['tn']),
      mcc: clean(q['mc']),
      raw: trimmed,
    );
  }

  /// The link handed to the UPI app. The QR's own fields are kept as they
  /// are (merchant QRs can be signed); only a missing amount and currency
  /// are filled in.
  String payLink({required int amountPaise}) {
    final lower = raw.toLowerCase();
    bool has(String key) => RegExp('[?&]$key=').hasMatch(lower);
    var link = raw;
    String sep() => link.contains('?') ? '&' : '?';
    final am = (amountPaise / 100).toStringAsFixed(2);
    if (!has('am')) {
      link += '${sep()}am=$am';
    } else if (this.amountPaise == null) {
      // "am=" with no value: fill it in.
      link = link.replaceFirstMapped(RegExp(r'([?&]am=)(?=&|$)', caseSensitive: false), (m) => '${m[1]}$am');
    }
    if (!has('cu')) link += '${sep()}cu=INR';
    return link;
  }

  /// Category suggested by the merchant category code, if any.
  String? get suggestedCategoryId => mccCategory(mcc);

  static String? mccCategory(String? mcc) {
    final code = int.tryParse(mcc ?? '');
    if (code == null || code == 0) return null;
    if (code == 5411 || code == 5422 || code == 5441 || code == 5451 || code == 5499) return 'groceries';
    if (code == 5812 || code == 5813 || code == 5814) return 'food';
    if (code == 5541 || code == 5542 || code == 5983) return 'fuel';
    if (code == 4111 || code == 4121 || code == 4131 || code == 4789 || code == 7523) return 'transport';
    if (code == 4112 || code == 4511 || code == 4722 || (code >= 3000 && code <= 3350) || code == 7011) return 'travel';
    if (code == 4812 || code == 4814 || code == 4899 || code == 4900) return 'bills';
    if (code == 5912 || code == 8011 || code == 8021 || code == 8062 || code == 8071 || code == 8099) return 'health';
    if (code == 7832 || code == 7841 || code == 7922 || code == 7991 || code == 7996 || code == 7999) return 'entertainment';
    if (code == 8211 || code == 8220 || code == 8241 || code == 8244 || code == 8249 || code == 8299) return 'education';
    if (code == 6513) return 'rent';
    if ((code >= 5300 && code <= 5399) || (code >= 5600 && code <= 5699) || code == 5732 ||
        code == 5944 || code == 5945 || code == 5977) {
      return 'shopping';
    }
    return null;
  }
}

enum UpiResult { success, failure, submitted, unknown }

/// The UPI app's reply, such as
/// "txnId=AXI123&responseCode=00&Status=SUCCESS&txnRef=abc&ApprovalRefNo=428612345678".
class UpiResponse {
  const UpiResponse({required this.result, this.reference});

  final UpiResult result;

  /// 12-digit bank reference when the app sends one; matches the bank SMS.
  final String? reference;

  static UpiResponse parse(String? response) {
    if (response == null || response.trim().isEmpty) {
      return const UpiResponse(result: UpiResult.unknown);
    }
    final fields = <String, String>{};
    for (final part in response.split('&')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      String decode(String v) {
        try {
          return Uri.decodeQueryComponent(v);
        } on ArgumentError {
          return v;
        }
      }

      fields[part.substring(0, i).trim().toLowerCase()] = decode(part.substring(i + 1)).trim();
    }
    final status = (fields['status'] ?? '').toUpperCase();
    final result = switch (status) {
      'SUCCESS' || 'SUCCESSFUL' => UpiResult.success,
      'FAILURE' || 'FAILED' => UpiResult.failure,
      'SUBMITTED' || 'PENDING' => UpiResult.submitted,
      _ => UpiResult.unknown,
    };
    String? reference;
    for (final key in ['approvalrefno', 'rrn', 'txnref', 'txnid']) {
      final v = fields[key];
      if (v != null && RegExp(r'^\d{12}$').hasMatch(v)) {
        reference = v;
        break;
      }
    }
    return UpiResponse(result: result, reference: reference);
  }
}
