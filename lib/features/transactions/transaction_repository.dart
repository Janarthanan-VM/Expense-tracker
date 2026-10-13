import 'package:sqflite_sqlcipher/sqflite.dart';

import 'txn.dart';

class TransactionRepository {
  TransactionRepository(this._db);

  final Database _db;

  static const String _notDeleted = 'deleted_at IS NULL';

  // ---------------------------------------------------------------- payees

  /// Key used to recognise the same payee again: UPI ID first, name second.
  static String? payeeMatchKey({String? vpa, String? name}) {
    final v = vpa?.trim().toLowerCase();
    if (v != null && v.isNotEmpty) return 'vpa:$v';
    final n = name?.trim().toLowerCase();
    if (n != null && n.isNotEmpty) return 'name:$n';
    return null;
  }

  /// Rules are kept separately for money paid and money received, so
  /// "Swiggy = Food" does not turn a Swiggy refund into an expense.
  static String ruleKey(TxnType type, String payeeKey) => '${type.name}|$payeeKey';

  /// Category kinds allowed for each direction.
  static String allowedKindsSql(TxnType type) =>
      type == TxnType.debit ? "('expense', 'transfer')" : "('income', 'transfer')";

  Future<String?> _rememberedCategoryFor(Txn txn) async {
    final key = payeeMatchKey(vpa: txn.payeeVpa, name: txn.payeeName);
    if (key == null) return null;
    final rows = await _db.rawQuery(
      'SELECT p.default_category_id AS id FROM payees p '
      'JOIN categories c ON c.id = p.default_category_id '
      'WHERE p.match_key = ? AND c.kind IN ${allowedKindsSql(txn.type)} '
      'LIMIT 1',
      [ruleKey(txn.type, key)],
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as String?;
  }

  // ---------------------------------------------------------------- writes

  /// Saves a new transaction. If the payee has a remembered category, it is
  /// applied automatically. Returns null if a transaction with the same UPI
  /// reference already exists (a duplicate from another source), including one
  /// the user deleted, so deleted payments are not captured again.
  Future<Txn?> add(Txn txn) async {
    final upiRef = txn.upiRef;
    if (upiRef != null && upiRef.isNotEmpty) {
      final existing = await _db.query(
        'transactions',
        columns: ['id'],
        where: 'upi_ref = ?',
        whereArgs: [upiRef],
        limit: 1,
      );
      if (existing.isNotEmpty) return null;
    }

    var toSave = txn;
    if (toSave.categoryId == null) {
      final remembered = await _rememberedCategoryFor(txn);
      if (remembered != null) {
        toSave = toSave.copyWith(
          categoryId: remembered,
          categorySource: CategorySource.rule,
          isReviewed: true,
        );
      }
    }

    await _db.insert('transactions', toSave.toMap());
    return toSave;
  }

  Future<void> update(Txn txn) => _db.update(
        'transactions',
        txn.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: [txn.id],
      );

  /// The user picked a category for this payment.
  ///
  /// With [rememberForPayee], future payments to the same payee get this
  /// category automatically, and older payments to that payee that are still
  /// uncategorized or unconfirmed are updated too.
  Future<void> setCategory(
    Txn txn,
    String categoryId, {
    bool rememberForPayee = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction((t) async {
      await t.update(
        'transactions',
        {
          'category_id': categoryId,
          'category_source': CategorySource.user.name,
          'is_reviewed': 1,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [txn.id],
      );

      if (!rememberForPayee) return;
      final key = payeeMatchKey(vpa: txn.payeeVpa, name: txn.payeeName);
      if (key == null) return;

      await t.rawInsert(
        '''
        INSERT INTO payees (id, match_key, display_name, vpa, default_category_id, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(match_key) DO UPDATE SET
          default_category_id = excluded.default_category_id,
          display_name = COALESCE(excluded.display_name, payees.display_name),
          updated_at = excluded.updated_at
        ''',
        [
          ruleKey(txn.type, key),
          ruleKey(txn.type, key),
          txn.payeeName,
          txn.payeeVpa,
          categoryId,
          now,
        ],
      );

      final matchesPayee = key.startsWith('vpa:')
          ? 'LOWER(TRIM(payee_vpa)) = ?'
          : 'LOWER(TRIM(payee_name)) = ?';
      await t.update(
        'transactions',
        {
          'category_id': categoryId,
          'category_source': CategorySource.rule.name,
          'is_reviewed': 1,
          'updated_at': now,
        },
        where: '$matchesPayee AND type = ? AND $_notDeleted AND id != ? '
            'AND (category_id IS NULL OR is_reviewed = 0)',
        whereArgs: [key.substring(key.indexOf(':') + 1), txn.type.name, txn.id],
      );
    });
  }

  /// Soft delete: the row is kept (hidden everywhere) so the same UPI payment
  /// is not auto-captured again later.
  Future<void> delete(String id) => _db.update(
        'transactions',
        {'deleted_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );

  // ---------------------------------------------------------------- reads

  Future<List<Txn>> recent({int limit = 8}) async {
    final rows = await _db.query(
      'transactions',
      where: _notDeleted,
      orderBy: 'txn_time DESC',
      limit: limit,
    );
    return rows.map(Txn.fromMap).toList();
  }

  /// All transactions, newest first, optionally filtered by text and by
  /// payment method (for example only cash).
  Future<List<Txn>> list({String search = '', PaymentMode? mode}) async {
    final query = search.trim();
    // Escape % and _ so they are searched literally.
    final escaped = query
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    const like = r"LIKE ? ESCAPE '\'";
    final where = <String>[_notDeleted];
    final args = <Object>[];
    if (query.isNotEmpty) {
      where.add('(payee_name $like OR payee_vpa $like OR note $like)');
      args.addAll(List.filled(3, '%$escaped%'));
    }
    if (mode != null) {
      where.add('payment_mode = ?');
      args.add(mode.name);
    }
    final rows = await _db.query(
      'transactions',
      where: where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'txn_time DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  /// Payments with no category, or with a suggested category not yet confirmed.
  Future<List<Txn>> toCategorize() async {
    final rows = await _db.query(
      'transactions',
      where: "$_notDeleted AND status != 'failed' "
          'AND (category_id IS NULL OR is_reviewed = 0)',
      orderBy: 'txn_time DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  Future<MonthSummary> monthSummary(DateTime anyDayInMonth) async {
    final start = DateTime(anyDayInMonth.year, anyDayInMonth.month);
    final end = DateTime(anyDayInMonth.year, anyDayInMonth.month + 1);
    final range = [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];

    // Uncategorized payments count as spending; transfers do not.
    final spentRows = await _db.rawQuery('''
      SELECT t.category_id AS category_id, SUM(t.amount_paise) AS total
      FROM transactions t
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.deleted_at IS NULL AND t.status = 'success' AND t.type = 'debit'
        AND t.txn_time >= ? AND t.txn_time < ?
        AND (c.kind IS NULL OR c.kind = 'expense')
      GROUP BY t.category_id
      ORDER BY total DESC
    ''', range);

    final incomeRows = await _db.rawQuery('''
      SELECT COALESCE(SUM(t.amount_paise), 0) AS total
      FROM transactions t
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.deleted_at IS NULL AND t.status = 'success' AND t.type = 'credit'
        AND t.txn_time >= ? AND t.txn_time < ?
        AND (c.kind IS NULL OR c.kind = 'income')
    ''', range);

    final modeRows = await _db.rawQuery('''
      SELECT t.payment_mode AS mode, SUM(t.amount_paise) AS total
      FROM transactions t
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.deleted_at IS NULL AND t.status = 'success' AND t.type = 'debit'
        AND t.txn_time >= ? AND t.txn_time < ?
        AND (c.kind IS NULL OR c.kind = 'expense')
      GROUP BY t.payment_mode
    ''', range);

    final spentByMode = <PaymentMode, int>{};
    for (final r in modeRows) {
      final mode =
          PaymentMode.values.asNameMap()[r['mode'] as String?] ?? PaymentMode.other;
      final total = (r['total'] as int?) ?? 0;
      if (total > 0) spentByMode[mode] = (spentByMode[mode] ?? 0) + total;
    }

    final byCategory = spentRows
        .map((r) => CategoryTotal(
              categoryId: r['category_id'] as String?,
              totalPaise: (r['total'] as int?) ?? 0,
            ))
        .toList();

    return MonthSummary(
      month: start,
      spentPaise: byCategory.fold(0, (sum, c) => sum + c.totalPaise),
      incomePaise: (incomeRows.first['total'] as int?) ?? 0,
      byCategory: byCategory,
      spentByMode: spentByMode,
    );
  }
}
