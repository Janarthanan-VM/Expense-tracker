import 'package:sqflite_sqlcipher/sqflite.dart';

import '../categories/default_categories.dart';
import '../detection/detected_payment.dart';
import '../reports/report_data.dart';
import 'txn.dart';

class TransactionRepository {
  TransactionRepository(this._db);

  final Database _db;

  static const String _notDeleted = 'deleted_at IS NULL';

  /// What a payment adds to spending: your share of a split bill, otherwise
  /// the full amount.
  static const String _spendSql =
      'CASE WHEN t.my_share_paise IS NOT NULL AND t.my_share_paise < t.amount_paise '
      'THEN t.my_share_paise ELSE t.amount_paise END';

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

  /// Category remembered for this payee ("Always use for ..."), if any.
  Future<String?> rememberedCategory({required TxnType type, String? vpa, String? name}) {
    final now = DateTime.now();
    return _rememberedCategoryFor(Txn(
      id: '',
      amountPaise: 1,
      type: type,
      status: TxnStatus.pending,
      source: TxnSource.scanPay,
      paymentMode: PaymentMode.upi,
      txnTime: now,
      createdAt: now,
      updatedAt: now,
      payeeVpa: vpa,
      payeeName: name,
    ));
  }

  /// Remembered payees with their category, newest first.
  Future<List<PayeeRule>> payeeRules() async {
    final rows = await _db.rawQuery('''
      SELECT p.match_key AS key, p.display_name AS name, p.vpa AS vpa,
             p.default_category_id AS category_id, p.updated_at AS updated_at
      FROM payees p
      WHERE p.default_category_id IS NOT NULL
      ORDER BY p.updated_at DESC
    ''');
    return [
      for (final r in rows)
        PayeeRule(
          key: r['key']! as String,
          name: r['name'] as String?,
          vpa: r['vpa'] as String?,
          categoryId: r['category_id']! as String,
          isDebit: !(r['key']! as String).startsWith('credit|'),
        ),
    ];
  }

  /// Forgets one "Always use for ..." rule. Payments keep their category.
  Future<void> deletePayeeRule(String key) =>
      _db.delete('payees', where: 'match_key = ?', whereArgs: [key]);

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

  /// Undoes [delete].
  Future<void> restore(String id) => _db.update(
        'transactions',
        {'deleted_at': null, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Records how a Scan & Pay payment ended. A bank [upiRef] is kept when it
  /// is not already used, so the bank SMS later merges into this payment.
  Future<void> setStatus(String id, TxnStatus status, {String? upiRef}) async {
    final updates = <String, Object?>{
      'status': status.name,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (upiRef != null) {
      final taken = await _db.query(
        'transactions',
        columns: ['id'],
        where: 'upi_ref = ? AND id != ?',
        whereArgs: [upiRef, id],
        limit: 1,
      );
      if (taken.isEmpty) updates['upi_ref'] = upiRef;
    }
    await _db.update('transactions', updates, where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------- detection

  /// Saves a payment found by automatic detection, or merges it into the
  /// transaction it duplicates. Returns true if anything changed.
  ///
  /// The same payment often arrives twice (UPI app notification and bank
  /// SMS). Matches are found by id, then UPI reference, then same amount and
  /// direction within 5 minutes.
  /// Saves or merges a detected payment. Returns true if anything changed.
  ///
  /// With [imported] (past SMS from the inbox) it returns true only when a
  /// new transaction was added, and a payment the user already deleted is
  /// never brought back, even without a UPI reference.
  Future<bool> upsertDetected(
    DetectedPayment e,
    Set<String> validCategoryIds, {
    bool imported = false,
  }) async {
    final pickedCategory =
        e.categoryId != null && validCategoryIds.contains(e.categoryId) ? e.categoryId : null;

    var existing = await byId(e.id, includeDeleted: true);
    if (existing != null && existing.deletedAt != null) return false;

    if (existing == null && e.upiRef != null) {
      final rows = await _db.query(
        'transactions',
        where: 'upi_ref = ?',
        whereArgs: [e.upiRef],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final match = Txn.fromMap(rows.first);
        if (match.deletedAt != null) return false;
        existing = match;
      }
    }

    if (existing == null && e.hasPayment) {
      existing = await _findNearDuplicate(e, includeDeleted: imported);
      if (existing != null && existing.deletedAt != null) return false;
    }

    if (existing != null) {
      final filled = await _fillMissing(existing, e);
      if (pickedCategory != null) {
        await setCategory(existing, pickedCategory);
        return !imported;
      }
      return filled && !imported;
    }

    if (!e.hasPayment) return false;

    final now = DateTime.now();
    final saved = await add(Txn(
      id: e.id,
      amountPaise: e.amountPaise!,
      type: e.isDebit! ? TxnType.debit : TxnType.credit,
      status: TxnStatus.success,
      source: e.source == 'sms' ? TxnSource.sms : TxnSource.notification,
      paymentMode: PaymentMode.values.asNameMap()[e.mode] ?? PaymentMode.upi,
      categoryId: pickedCategory,
      categorySource: pickedCategory == null ? null : CategorySource.user,
      isReviewed: pickedCategory != null,
      payeeName: e.payeeName,
      payeeVpa: e.payeeVpa,
      upiRef: e.upiRef,
      upiApp: e.app,
      txnTime: e.time ?? now,
      createdAt: now,
      updatedAt: now,
    ));
    return saved != null;
  }

  /// The same payment seen from another place (an SMS and a UPI app
  /// notification, or one you typed in yourself) within a few minutes.
  ///
  /// Live payments only match a copy from a *different* source, and never one
  /// with a different UPI reference, so two real ₹10 payments a minute apart
  /// stay two payments. Imports ([includeDeleted]) also match the same source,
  /// because an imported SMS may already be saved under another id.
  Future<Txn?> _findNearDuplicate(DetectedPayment e, {bool includeDeleted = false}) async {
    final time = (e.time ?? DateTime.now()).millisecondsSinceEpoch;
    const window = 5 * 60 * 1000;
    final source = e.source == 'sms' ? TxnSource.sms.name : TxnSource.notification.name;
    // Built without null arguments: some SQLite bindings reject them.
    final where = StringBuffer(includeDeleted ? '1 = 1' : _notDeleted)
      ..write(' AND amount_paise = ? AND type = ? AND txn_time BETWEEN ? AND ?')
      ..write(" AND (source != 'manual' OR payment_mode = ?)");
    final args = <Object>[
      e.amountPaise!,
      e.isDebit! ? TxnType.debit.name : TxnType.credit.name,
      time - window,
      time + window,
      e.mode ?? PaymentMode.upi.name,
    ];
    if (e.upiRef != null) {
      where.write(' AND (upi_ref IS NULL OR upi_ref = ?)');
      args.add(e.upiRef!);
    }
    if (!includeDeleted) {
      where.write(' AND source != ?');
      args.add(source);
    }
    final rows = await _db.query(
      'transactions',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'ABS(txn_time - $time)',
      limit: 1,
    );
    return rows.isEmpty ? null : Txn.fromMap(rows.first);
  }

  /// Adds payee, UPI ID, reference or app when the saved payment lacks them.
  Future<bool> _fillMissing(Txn existing, DetectedPayment e) async {
    final updates = <String, Object?>{};
    // A bank SMS or app notification confirms a Scan & Pay payment that was
    // still waiting for its result.
    if (existing.status == TxnStatus.pending && e.hasPayment) {
      updates['status'] = TxnStatus.success.name;
    }
    if (existing.payeeName == null && e.payeeName != null) updates['payee_name'] = e.payeeName;
    if (existing.payeeVpa == null && e.payeeVpa != null) updates['payee_vpa'] = e.payeeVpa;
    if (existing.upiApp == null && e.app != null) updates['upi_app'] = e.app;
    if (existing.upiRef == null && e.upiRef != null) {
      final taken = await _db.query(
        'transactions',
        columns: ['id'],
        where: 'upi_ref = ? AND id != ?',
        whereArgs: [e.upiRef, existing.id],
        limit: 1,
      );
      if (taken.isEmpty) updates['upi_ref'] = e.upiRef;
    }
    if (updates.isEmpty) return false;
    updates['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await _db.update('transactions', updates, where: 'id = ?', whereArgs: [existing.id]);
    return true;
  }

  /// Most used visible categories in the last 90 days, for the buttons on the
  /// payment notification. Unused categories follow in their normal order.
  Future<List<String>> topCategoryIds(TxnType type, {int limit = 2}) async {
    final since = DateTime.now().subtract(const Duration(days: 90)).millisecondsSinceEpoch;
    final kind = type == TxnType.debit ? 'expense' : 'income';
    final rows = await _db.rawQuery('''
      SELECT c.id AS id
      FROM categories c
      LEFT JOIN transactions t
        ON t.category_id = c.id AND t.deleted_at IS NULL
       AND t.txn_time >= ? AND t.type = ?
      WHERE (c.kind = ? OR (? = 'credit' AND c.id = '$splitSettlementId')) AND c.is_hidden = 0
      GROUP BY c.id
      ORDER BY COUNT(t.id) DESC, c.sort_order, c.name
      LIMIT ?
    ''', [since, type.name, kind, type.name, limit]);
    return rows.map((r) => r['id']! as String).toList();
  }

  // ---------------------------------------------------------------- reads

  Future<Txn?> byId(String id, {bool includeDeleted = false}) async {
    final rows = await _db.query(
      'transactions',
      where: includeDeleted ? 'id = ?' : 'id = ? AND $_notDeleted',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Txn.fromMap(rows.first);
  }

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
  Future<List<Txn>> list({String search = '', PaymentMode? mode, TxnType? type}) async {
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
      // "250" or "₹1,249.50" also finds that exact amount.
      final amount = double.tryParse(query.replaceAll(RegExp(r'[₹,\s]|rs\.?', caseSensitive: false), ''));
      final amountPaise = amount == null || amount <= 0 ? null : (amount * 100).round();
      where.add(
        '(payee_name $like OR payee_vpa $like OR note $like OR upi_app $like'
        '${amountPaise == null ? '' : ' OR amount_paise = ?'})',
      );
      args.addAll(List.filled(4, '%$escaped%'));
      if (amountPaise != null) args.add(amountPaise);
    }
    if (mode != null) {
      where.add('payment_mode = ?');
      args.add(mode.name);
    }
    if (type != null) {
      where.add('type = ?');
      args.add(type.name);
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

  // ---------------------------------------------------------------- duplicates

  static const String _ignoredDuplicatesKey = 'ignored_duplicates';

  /// Groups of payments that look like one payment recorded more than once:
  /// same direction and amount within [window] of each other. Two payments
  /// with different bank references, or to different UPI IDs, are never
  /// grouped. Groups the user marked "Not duplicates" are left out.
  /// Newest group first.
  Future<List<List<Txn>>> duplicateGroups({Duration window = const Duration(minutes: 10)}) async {
    final rows = await _db.query(
      'transactions',
      where: "$_notDeleted AND status != 'failed'",
      orderBy: 'txn_time ASC',
    );
    final txns = rows.map(Txn.fromMap).toList();
    final ignored = await _ignoredDuplicates();
    final used = <String>{};
    final groups = <List<Txn>>[];
    for (var i = 0; i < txns.length; i++) {
      final first = txns[i];
      if (used.contains(first.id)) continue;
      final group = [first];
      for (var j = i + 1; j < txns.length; j++) {
        final other = txns[j];
        if (other.txnTime.difference(first.txnTime) > window) break;
        if (!used.contains(other.id) && group.every((t) => _looksSame(t, other))) group.add(other);
      }
      if (group.length < 2 || ignored.contains(_signature(group))) continue;
      used.addAll(group.map((t) => t.id));
      groups.add(group);
    }
    return groups.reversed.toList();
  }

  static bool _looksSame(Txn a, Txn b) {
    if (a.type != b.type || a.amountPaise != b.amountPaise) return false;
    if (a.upiRef != null && b.upiRef != null && a.upiRef != b.upiRef) return false;
    final va = a.payeeVpa?.trim().toLowerCase() ?? '';
    final vb = b.payeeVpa?.trim().toLowerCase() ?? '';
    return va.isEmpty || vb.isEmpty || va == vb;
  }

  static String _signature(List<Txn> group) => (group.map((t) => t.id).toList()..sort()).join('|');

  Future<Set<String>> _ignoredDuplicates() async {
    final rows = await _db.query('meta', where: 'key = ?', whereArgs: [_ignoredDuplicatesKey]);
    if (rows.isEmpty) return {};
    return (rows.first['value']! as String).split('\n').where((s) => s.isNotEmpty).toSet();
  }

  /// Remembers that this group is not a duplicate, so it is not shown again.
  Future<void> ignoreDuplicates(List<Txn> group) async {
    final ignored = await _ignoredDuplicates()
      ..add(_signature(group));
    await _db.insert(
      'meta',
      {'key': _ignoredDuplicatesKey, 'value': ignored.join('\n')},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The payment to keep from a duplicate group: one with a confirmed
  /// category, then any category, then a bank reference, then the earliest.
  static Txn keeperOf(List<Txn> group) {
    int score(Txn t) =>
        (t.categoryId != null && t.isReviewed ? 4 : 0) +
        (t.categoryId != null ? 2 : 0) +
        (t.upiRef != null ? 1 : 0);
    final sorted = [...group]
      ..sort((a, b) {
        final byScore = score(b).compareTo(score(a));
        return byScore != 0 ? byScore : a.txnTime.compareTo(b.txnTime);
      });
    return sorted.first;
  }

  /// Spending per day of the month (index 0 = the 1st), counted the same way
  /// as the month total: successful debits, excluding transfers.
  Future<List<int>> dailySpend(DateTime anyDayInMonth) async {
    final start = DateTime(anyDayInMonth.year, anyDayInMonth.month);
    final end = DateTime(anyDayInMonth.year, anyDayInMonth.month + 1);
    final days = end.difference(start).inDays;
    final rows = await _db.rawQuery('''
      SELECT t.txn_time AS at, $_spendSql AS amount
      FROM transactions t
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.deleted_at IS NULL AND t.status = 'success' AND t.type = 'debit'
        AND t.txn_time >= ? AND t.txn_time < ?
        AND (c.kind IS NULL OR c.kind = 'expense')
    ''', [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch]);
    final totals = List<int>.filled(days, 0);
    for (final r in rows) {
      // Day of month in the phone's own time zone.
      final day = DateTime.fromMillisecondsSinceEpoch(r['at']! as int).day;
      if (day >= 1 && day <= days) totals[day - 1] += r['amount']! as int;
    }
    return totals;
  }

  Future<MonthSummary> monthSummary(DateTime anyDayInMonth) async {
    final start = DateTime(anyDayInMonth.year, anyDayInMonth.month);
    final end = DateTime(anyDayInMonth.year, anyDayInMonth.month + 1);
    final range = [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];

    // Uncategorized payments count as spending; transfers do not.
    final spentRows = await _db.rawQuery('''
      SELECT t.category_id AS category_id, SUM($_spendSql) AS total
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

    final paidBackRows = await _db.rawQuery('''
      SELECT COALESCE(SUM(t.amount_paise), 0) AS total
      FROM transactions t
      WHERE t.deleted_at IS NULL AND t.status = 'success' AND t.type = 'credit'
        AND t.category_id = '$splitSettlementId'
        AND t.txn_time >= ? AND t.txn_time < ?
    ''', range);

    final modeRows = await _db.rawQuery('''
      SELECT t.payment_mode AS mode, SUM($_spendSql) AS total
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
      paidBackPaise: (paidBackRows.first['total'] as int?) ?? 0,
    );
  }

  // ---------------------------------------------------------------- reports

  /// Totals, pies and top payees for [start] (inclusive) to [end] (exclusive).
  Future<PeriodReport> report(DateTime start, DateTime end) async {
    final range = [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    const spendable = "t.deleted_at IS NULL AND t.status = 'success' AND t.type = 'debit' "
        'AND t.txn_time >= ? AND t.txn_time < ? '
        "AND (c.kind IS NULL OR c.kind = 'expense')";

    final spendRows = await _db.rawQuery('''
      SELECT t.category_id AS category_id, SUM($_spendSql) AS total
      FROM transactions t LEFT JOIN categories c ON c.id = t.category_id
      WHERE $spendable
      GROUP BY t.category_id ORDER BY total DESC
    ''', range);

    // Money in by category; own-account transfers are not money received.
    final receiveRows = await _db.rawQuery('''
      SELECT t.category_id AS category_id, SUM(t.amount_paise) AS total
      FROM transactions t LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.deleted_at IS NULL AND t.status = 'success' AND t.type = 'credit'
        AND t.txn_time >= ? AND t.txn_time < ?
        AND (c.kind IS NULL OR c.kind = 'income' OR t.category_id = '$splitSettlementId')
      GROUP BY t.category_id ORDER BY total DESC
    ''', range);

    final payeeRows = await _db.rawQuery('''
      SELECT COALESCE(NULLIF(TRIM(t.payee_name), ''), t.payee_vpa) AS who,
             SUM($_spendSql) AS total, COUNT(*) AS n
      FROM transactions t LEFT JOIN categories c ON c.id = t.category_id
      WHERE $spendable
        AND COALESCE(NULLIF(TRIM(t.payee_name), ''), t.payee_vpa) IS NOT NULL
      GROUP BY LOWER(COALESCE(NULLIF(TRIM(t.payee_name), ''), t.payee_vpa))
      ORDER BY total DESC LIMIT 5
    ''', range);

    List<Slice> slices(List<Map<String, Object?>> rows) => [
          for (final r in rows)
            if (((r['total'] as int?) ?? 0) > 0)
              Slice(categoryId: r['category_id'] as String?, paise: r['total']! as int),
        ];
    final spending = slices(spendRows);
    final receiving = slices(receiveRows);
    final paidBack = receiving
        .where((s) => s.categoryId == splitSettlementId)
        .fold<int>(0, (sum, s) => sum + s.paise);
    final received = receiving.fold<int>(0, (sum, s) => sum + s.paise);

    return PeriodReport(
      start: start,
      end: end,
      spentPaise: spending.fold(0, (sum, s) => sum + s.paise),
      incomePaise: received - paidBack,
      paidBackPaise: paidBack,
      spending: spending,
      receiving: receiving,
      topPayees: [
        for (final r in payeeRows)
          PayeeTotal(name: r['who']! as String, paise: r['total']! as int, count: r['n']! as int),
      ],
    );
  }

  /// Money out (your spending) and money in (income, plus friends paying you
  /// back) for each of [months] months ending with [lastMonth].
  Future<List<MonthFlow>> monthlyFlow(DateTime lastMonth, {int months = 6}) async {
    final first = DateTime(lastMonth.year, lastMonth.month - months + 1);
    final end = DateTime(lastMonth.year, lastMonth.month + 1);
    final rows = await _db.rawQuery('''
      SELECT t.txn_time AS at, t.type AS type,
             $_spendSql AS spend, t.amount_paise AS amount, c.kind AS kind, t.category_id AS cat
      FROM transactions t LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.deleted_at IS NULL AND t.status = 'success'
        AND t.txn_time >= ? AND t.txn_time < ?
    ''', [first.millisecondsSinceEpoch, end.millisecondsSinceEpoch]);

    final out = List<int>.filled(months, 0);
    final inn = List<int>.filled(months, 0);
    for (final r in rows) {
      final at = DateTime.fromMillisecondsSinceEpoch(r['at']! as int);
      final i = (at.year - first.year) * 12 + at.month - first.month;
      if (i < 0 || i >= months) continue;
      final kind = r['kind'] as String?;
      if (r['type'] == 'debit') {
        if (kind == null || kind == 'expense') out[i] += r['spend']! as int;
      } else if (kind == null || kind == 'income' || r['cat'] == splitSettlementId) {
        inn[i] += r['amount']! as int;
      }
    }
    return [
      for (var i = 0; i < months; i++)
        MonthFlow(month: DateTime(first.year, first.month + i), outPaise: out[i], inPaise: inn[i]),
    ];
  }

  /// What friends still owe you across all split bills: the parts of shared
  /// bills that were not yours, minus what they have paid back. Never below 0.
  Future<int> owedToYou() async {
    final rows = await _db.rawQuery('''
      SELECT
        COALESCE((SELECT SUM(amount_paise - my_share_paise) FROM transactions
          WHERE deleted_at IS NULL AND status = 'success' AND type = 'debit'
            AND my_share_paise IS NOT NULL AND my_share_paise < amount_paise), 0) AS owed,
        COALESCE((SELECT SUM(amount_paise) FROM transactions
          WHERE deleted_at IS NULL AND status = 'success' AND type = 'credit'
            AND category_id = '$splitSettlementId'), 0) AS repaid
    ''');
    final owed = (rows.first['owed'] as int?) ?? 0;
    final repaid = (rows.first['repaid'] as int?) ?? 0;
    return owed - repaid > 0 ? owed - repaid : 0;
  }

  /// Marks a bill as shared: [mySharePaise] is your part. Null removes the split.
  Future<void> setMyShare(String id, int? mySharePaise) => _db.update(
        'transactions',
        {'my_share_paise': mySharePaise, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );
}
