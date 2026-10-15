/// Debit = money went out, credit = money came in.
enum TxnType { debit, credit }

enum TxnStatus { success, pending, failed }

/// How the money was paid or received.
enum PaymentMode { cash, upi, card, bank, other }

extension PaymentModeLabel on PaymentMode {
  String get label => switch (this) {
        PaymentMode.cash => 'Cash',
        PaymentMode.upi => 'UPI',
        PaymentMode.card => 'Card',
        PaymentMode.bank => 'Bank transfer',
        PaymentMode.other => 'Other',
      };

  /// Short label for chips and list rows.
  String get shortLabel => this == PaymentMode.bank ? 'Bank' : label;
}

/// Where the transaction came from.
enum TxnSource { manual, scanPay, notification, sms, ocr, statement }

/// How the category was set: suggested by the app, applied from a
/// "remember this payee" rule, or picked by the user.
enum CategorySource { auto, rule, user }

class Txn {
  const Txn({
    required this.id,
    required this.amountPaise,
    required this.type,
    required this.status,
    required this.source,
    required this.paymentMode,
    required this.txnTime,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.categorySource,
    this.isReviewed = false,
    this.payeeName,
    this.payeeVpa,
    this.upiRef,
    this.upiApp,
    this.note,
    this.deletedAt,
    this.mySharePaise,
  });

  final String id;
  final int amountPaise;
  final TxnType type;
  final TxnStatus status;
  final TxnSource source;
  final PaymentMode paymentMode;
  final String? categoryId;
  final CategorySource? categorySource;

  /// False until the user has picked or confirmed the category.
  final bool isReviewed;
  final String? payeeName;
  final String? payeeVpa;
  final String? upiRef;
  final String? upiApp;
  final String? note;
  final DateTime txnTime;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// For a split bill: the part you paid for yourself. Null = not split.
  /// Spending totals count this instead of [amountPaise].
  final int? mySharePaise;

  bool get isSplit => mySharePaise != null && mySharePaise! < amountPaise;

  /// What this payment adds to your spending.
  int get spendPaise => isSplit ? mySharePaise! : amountPaise;

  /// What friends owe you for this bill.
  int get owedPaise => isSplit ? amountPaise - mySharePaise! : 0;

  /// Shown in the "To categorize" list.
  bool get needsCategory =>
      status != TxnStatus.failed && (categoryId == null || !isReviewed);

  /// Best label for "who" this payment was with.
  String? get payeeLabel {
    final name = payeeName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final vpa = payeeVpa?.trim();
    if (vpa != null && vpa.isNotEmpty) return vpa;
    return null;
  }

  Txn copyWith({
    String? categoryId,
    CategorySource? categorySource,
    bool? isReviewed,
    DateTime? updatedAt,
  }) =>
      Txn(
        id: id,
        amountPaise: amountPaise,
        type: type,
        status: status,
        source: source,
        paymentMode: paymentMode,
        txnTime: txnTime,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        categoryId: categoryId ?? this.categoryId,
        categorySource: categorySource ?? this.categorySource,
        isReviewed: isReviewed ?? this.isReviewed,
        payeeName: payeeName,
        payeeVpa: payeeVpa,
        upiRef: upiRef,
        upiApp: upiApp,
        note: note,
        deletedAt: deletedAt,
        mySharePaise: mySharePaise,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'amount_paise': amountPaise,
        'type': type.name,
        'status': status.name,
        'source': source.name,
        'payment_mode': paymentMode.name,
        'category_id': categoryId,
        'category_source': categorySource?.name,
        'is_reviewed': isReviewed ? 1 : 0,
        'payee_name': payeeName,
        'payee_vpa': payeeVpa,
        'upi_ref': upiRef,
        'upi_app': upiApp,
        'note': note,
        'txn_time': txnTime.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
        'my_share_paise': mySharePaise,
      };

  factory Txn.fromMap(Map<String, Object?> m) {
    final categorySource = m['category_source'] as String?;
    final deletedAt = m['deleted_at'] as int?;
    return Txn(
      id: m['id']! as String,
      amountPaise: m['amount_paise']! as int,
      type: TxnType.values.byName(m['type']! as String),
      status: TxnStatus.values.byName(m['status']! as String),
      source: TxnSource.values.byName(m['source']! as String),
      paymentMode: PaymentMode.values.asNameMap()[m['payment_mode'] as String?] ??
          PaymentMode.other,
      categoryId: m['category_id'] as String?,
      categorySource:
          categorySource == null ? null : CategorySource.values.byName(categorySource),
      isReviewed: m['is_reviewed'] == 1,
      payeeName: m['payee_name'] as String?,
      payeeVpa: m['payee_vpa'] as String?,
      upiRef: m['upi_ref'] as String?,
      upiApp: m['upi_app'] as String?,
      note: m['note'] as String?,
      txnTime: DateTime.fromMillisecondsSinceEpoch(m['txn_time']! as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at']! as int),
      deletedAt: deletedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(deletedAt),
      mySharePaise: m['my_share_paise'] as int?,
    );
  }
}

class CategoryTotal {
  const CategoryTotal({required this.categoryId, required this.totalPaise});

  /// Null means "not categorized yet".
  final String? categoryId;
  final int totalPaise;
}

class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.spentPaise,
    required this.incomePaise,
    required this.byCategory,
    required this.spentByMode,
    this.paidBackPaise = 0,
  });

  final DateTime month;
  final int spentPaise;
  final int incomePaise;

  /// Spending per category, largest first.
  final List<CategoryTotal> byCategory;

  /// Spending per payment method (cash, UPI, ...). Methods with no spending
  /// are left out.
  final Map<PaymentMode, int> spentByMode;

  /// Money friends sent back for split bills this month (not income).
  final int paidBackPaise;
}

/// An "Always use this category for ..." rule.
class PayeeRule {
  const PayeeRule({
    required this.key,
    required this.categoryId,
    required this.isDebit,
    this.name,
    this.vpa,
  });

  /// Stored key, e.g. "debit|vpa:shop@okaxis".
  final String key;
  final String categoryId;

  /// The rule applies to money paid (true) or money received (false).
  final bool isDebit;
  final String? name;
  final String? vpa;

  String get label {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final v = vpa?.trim();
    if (v != null && v.isNotEmpty) return v;
    return key.substring(key.indexOf(':') + 1);
  }
}
