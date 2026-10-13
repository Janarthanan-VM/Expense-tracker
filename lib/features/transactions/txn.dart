/// Debit = money went out, credit = money came in.
enum TxnType { debit, credit }

enum TxnStatus { success, pending, failed }

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
  });

  final String id;
  final int amountPaise;
  final TxnType type;
  final TxnStatus status;
  final TxnSource source;
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
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'amount_paise': amountPaise,
        'type': type.name,
        'status': status.name,
        'source': source.name,
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
  });

  final DateTime month;
  final int spentPaise;
  final int incomePaise;

  /// Spending per category, largest first.
  final List<CategoryTotal> byCategory;
}
