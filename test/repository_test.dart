// Runs the real repository code against SQLite on the build machine
// (sqflite_common_ffi), to check saving, duplicates, Scan & Pay status,
// search, undo and payee rules.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:expense_tracker/core/db/app_database.dart';
import 'package:expense_tracker/features/detection/detected_payment.dart';
import 'package:expense_tracker/features/transactions/transaction_repository.dart';
import 'package:expense_tracker/features/transactions/txn.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late TransactionRepository repo;
  final validIds = <String>{'food', 'salary', 'received', 'groceries'};
  final now = DateTime.now();

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.createSchema(db);
    repo = TransactionRepository(db);
  });

  tearDown(() => db.close());

  DetectedPayment payment(
    String id, {
    int paise = 100,
    bool debit = false,
    String source = 'notification',
    String? ref,
    DateTime? at,
    String? app,
  }) =>
      DetectedPayment(
        id: id,
        amountPaise: paise,
        isDebit: debit,
        mode: 'upi',
        source: source,
        app: app ?? (source == 'sms' ? 'UNIONB ••1094' : 'Google Pay'),
        time: at ?? now,
        upiRef: ref,
      );

  test('a Google Pay "received" notification is saved and counted', () async {
    expect(await repo.upsertDetected(payment('gp-1'), validIds), isTrue);
    final list = await repo.list();
    expect(list, hasLength(1));
    expect(list.first.type, TxnType.credit);
    final summary = await repo.monthSummary(now);
    expect(summary.incomePaise, 100);
    expect((await repo.toCategorize()), hasLength(1));
  });

  test('two real payments of the same amount a minute apart stay separate', () async {
    await repo.upsertDetected(payment('s1', source: 'sms', debit: true, ref: '131306780290'), validIds);
    await repo.upsertDetected(
      payment('s2', source: 'sms', debit: true, ref: '131306780291', at: now.add(const Duration(minutes: 1))),
      validIds,
    );
    expect(await repo.list(), hasLength(2));
  });

  test('two same-amount SMS without references stay separate', () async {
    await repo.upsertDetected(payment('s1', source: 'sms', debit: true), validIds);
    await repo.upsertDetected(
      payment('s2', source: 'sms', debit: true, at: now.add(const Duration(minutes: 1))),
      validIds,
    );
    expect(await repo.list(), hasLength(2));
  });

  test('the same payment from Google Pay and the bank SMS is saved once', () async {
    await repo.upsertDetected(payment('gp-1'), validIds);
    final second = await repo.upsertDetected(
      payment('sms-1', source: 'sms', ref: '665472310076', at: now.add(const Duration(seconds: 20))),
      validIds,
    );
    final list = await repo.list();
    expect(list, hasLength(1));
    expect(list.first.upiRef, '665472310076', reason: 'the SMS fills in the reference');
    expect(second, isTrue);
  });

  test('importing the same SMS twice adds it once', () async {
    final e = payment('sms-abc', source: 'sms', ref: '428600001111', debit: true);
    expect(await repo.upsertDetected(e, validIds, imported: true), isTrue);
    expect(await repo.upsertDetected(e, validIds, imported: true), isFalse);
    expect(await repo.list(), hasLength(1));
  });

  test('a deleted payment is not imported again', () async {
    final e = payment('sms-del', source: 'sms', debit: true);
    await repo.upsertDetected(e, validIds);
    await repo.delete('sms-del');
    expect(await repo.upsertDetected(e, validIds, imported: true), isFalse);
    expect(await repo.list(), isEmpty);
  });

  test('a category picked from the notification is applied', () async {
    await repo.upsertDetected(payment('gp-2'), validIds);
    await repo.upsertDetected(
      const DetectedPayment(id: 'gp-2', categoryId: 'received'),
      validIds,
    );
    final t = (await repo.list()).single;
    expect(t.categoryId, 'received');
    expect(t.isReviewed, isTrue);
  });

  test('daily spending adds up debits per day', () async {
    await repo.upsertDetected(payment('d1', source: 'sms', debit: true, paise: 25000), validIds);
    final days = await repo.dailySpend(now);
    expect(days[now.day - 1], 25000);
  });

  // ------------------------------------------------------------ v0.6.0

  Txn manual(String id, int paise, {TxnType type = TxnType.debit, String? payee, String? vpa, DateTime? at}) {
    final when = at ?? now;
    return Txn(
      id: id,
      amountPaise: paise,
      type: type,
      status: TxnStatus.success,
      source: TxnSource.manual,
      paymentMode: PaymentMode.cash,
      txnTime: when,
      createdAt: when,
      updatedAt: when,
      payeeName: payee,
      payeeVpa: vpa,
    );
  }

  test('a manual expense is saved, counted, and listed', () async {
    await repo.add(manual('m1', 6000, payee: 'Auto'));
    final s = await repo.monthSummary(now);
    expect(s.spentPaise, 6000);
    expect(s.spentByMode[PaymentMode.cash], 6000);
    expect((await repo.list()).single.payeeName, 'Auto');
  });

  test('search finds a payment by its amount', () async {
    await repo.add(manual('m1', 25000, payee: 'Tea'));
    await repo.add(manual('m2', 9900, payee: 'Bus'));
    expect((await repo.list(search: '250')).single.id, 'm1');
    expect((await repo.list(search: '₹99')).single.id, 'm2');
    expect((await repo.list(search: 'bus')).single.id, 'm2');
  });

  test('a deleted payment can be restored with Undo', () async {
    await repo.add(manual('m1', 100));
    await repo.delete('m1');
    expect(await repo.list(), isEmpty);
    await repo.restore('m1');
    expect(await repo.list(), hasLength(1));
  });

  test('a waiting Scan & Pay payment is confirmed by the bank SMS', () async {
    final pending = Txn(
      id: 'sp1',
      amountPaise: 25000,
      type: TxnType.debit,
      status: TxnStatus.pending,
      source: TxnSource.scanPay,
      paymentMode: PaymentMode.upi,
      txnTime: now,
      createdAt: now,
      updatedAt: now,
      payeeName: 'Sri Stores',
      payeeVpa: 'shop@okaxis',
    );
    await repo.add(pending);
    expect((await repo.monthSummary(now)).spentPaise, 0, reason: 'waiting payments are not counted yet');
    await repo.upsertDetected(
      payment('sms-x', source: 'sms', debit: true, paise: 25000, ref: '428612345678',
          at: now.add(const Duration(minutes: 1))),
      validIds,
    );
    final list = await repo.list();
    expect(list, hasLength(1));
    expect(list.single.status, TxnStatus.success);
    expect(list.single.upiRef, '428612345678');
    expect((await repo.monthSummary(now)).spentPaise, 25000);
  });

  test('setStatus records success with the bank reference', () async {
    await repo.add(manual('sp2', 100).copyWith());
    await repo.setStatus('sp2', TxnStatus.success, upiRef: '428600000001');
    expect((await repo.byId('sp2'))!.upiRef, '428600000001');
  });

  test('payee rules are listed, applied to new payments, and can be forgotten', () async {
    final first = manual('r1', 500, vpa: 'swiggy@icici', payee: 'Swiggy');
    await repo.add(first);
    await repo.setCategory(first, 'food', rememberForPayee: true);
    final rules = await repo.payeeRules();
    expect(rules, hasLength(1));
    expect(rules.single.categoryId, 'food');
    expect(rules.single.isDebit, isTrue);

    final second = await repo.add(manual('r2', 700, vpa: 'swiggy@icici'));
    expect(second!.categoryId, 'food', reason: 'remembered category applied');
    expect(await repo.rememberedCategory(type: TxnType.debit, vpa: 'swiggy@icici'), 'food');
    expect(await repo.rememberedCategory(type: TxnType.credit, vpa: 'swiggy@icici'), isNull,
        reason: 'a refund from Swiggy is not food spending');

    await repo.deletePayeeRule(rules.single.key);
    expect(await repo.payeeRules(), isEmpty);
    expect((await repo.add(manual('r3', 900, vpa: 'swiggy@icici')))!.categoryId, isNull);
  });

  test('transfers between own accounts are not spending or income', () async {
    final t = manual('t1', 100000);
    await repo.add(t);
    await repo.setCategory(t, 'self_transfer');
    expect((await repo.monthSummary(now)).spentPaise, 0);
  });

  test('last month is summarised separately', () async {
    final lastMonth = DateTime(now.year, now.month - 1, 10, 12);
    await repo.add(manual('old', 4000, at: lastMonth));
    await repo.add(manual('new', 1000));
    expect((await repo.monthSummary(lastMonth)).spentPaise, 4000);
    expect((await repo.monthSummary(now)).spentPaise, 1000);
    expect((await repo.dailySpend(lastMonth))[9], 4000);
  });

  // ------------------------------------------------------------ split bills (v0.7.0)

  test('a split bill counts only your share as spending', () async {
    await repo.add(manual('dinner', 100000, payee: 'Restaurant'));
    await repo.setMyShare('dinner', 25000);
    final s = await repo.monthSummary(now);
    expect(s.spentPaise, 25000);
    expect((await repo.dailySpend(now))[now.day - 1], 25000);
    expect(await repo.owedToYou(), 75000);
  });

  test('friends paying back reduces what they owe and is not income', () async {
    await repo.add(manual('dinner', 100000));
    await repo.setMyShare('dinner', 25000);
    final back = manual('ravi', 25000, type: TxnType.credit, payee: 'Ravi');
    await repo.add(back);
    await repo.setCategory(back, 'split_settlement');

    final s = await repo.monthSummary(now);
    expect(s.incomePaise, 0, reason: 'paying back is not income');
    expect(s.paidBackPaise, 25000);
    expect(await repo.owedToYou(), 50000);
  });

  test('owed never goes below zero', () async {
    final back = manual('extra', 5000, type: TxnType.credit);
    await repo.add(back);
    await repo.setCategory(back, 'split_settlement');
    expect(await repo.owedToYou(), 0);
  });

  test('removing a split counts the full bill again', () async {
    await repo.add(manual('cab', 60000));
    await repo.setMyShare('cab', 20000);
    await repo.setMyShare('cab', null);
    expect((await repo.monthSummary(now)).spentPaise, 60000);
    expect(await repo.owedToYou(), 0);
  });

  test('a deleted split bill no longer counts as owed', () async {
    await repo.add(manual('movie', 80000));
    await repo.setMyShare('movie', 20000);
    await repo.delete('movie');
    expect(await repo.owedToYou(), 0);
  });

  test('"Paid back by friends" is offered for money received', () async {
    final ids = await repo.topCategoryIds(TxnType.credit, limit: 10);
    expect(ids, contains('split_settlement'));
    expect(await repo.topCategoryIds(TxnType.debit, limit: 30), isNot(contains('split_settlement')));
  });

  // ------------------------------------------------------------ reports (v0.8.0)

  test('report: pies, totals and top payees for a month', () async {
    final food = manual('f1', 30000, payee: 'Swiggy');
    final food2 = manual('f2', 20000, payee: 'swiggy');
    final rent = manual('r1', 600000, payee: 'Landlord');
    for (final t in [food, food2, rent]) {
      await repo.add(t);
    }
    await repo.setCategory(food, 'food');
    await repo.setCategory(food2, 'food');
    await repo.setCategory(rent, 'rent');
    final salary = manual('s1', 4500000, type: TxnType.credit, payee: 'Acme');
    await repo.add(salary);
    await repo.setCategory(salary, 'salary');
    final back = manual('b1', 10000, type: TxnType.credit, payee: 'Ravi');
    await repo.add(back);
    await repo.setCategory(back, 'split_settlement');
    final own = manual('o1', 99900, type: TxnType.credit);
    await repo.add(own);
    await repo.setCategory(own, 'self_transfer');

    final start = DateTime(now.year, now.month);
    final r = await repo.report(start, DateTime(now.year, now.month + 1));
    expect(r.spentPaise, 650000);
    expect(r.spending.first.categoryId, 'rent');
    expect(r.spending.map((x) => x.categoryId), containsAll(['rent', 'food']));
    expect(r.incomePaise, 4500000, reason: 'paid back and own transfers are not income');
    expect(r.paidBackPaise, 10000);
    expect(r.receiving.map((x) => x.categoryId), isNot(contains('self_transfer')));
    expect(r.topPayees.first.name, 'Landlord');
    final swiggy = r.topPayees.firstWhere((p) => p.name.toLowerCase() == 'swiggy');
    expect(swiggy.count, 2, reason: 'names are grouped regardless of case');
    expect(swiggy.paise, 50000);
  });

  test('report for a year includes every month of it', () async {
    await repo.add(manual('jan', 1000, at: DateTime(now.year, 1, 15, 10)));
    await repo.add(manual('cur', 2000));
    final r = await repo.report(DateTime(now.year), DateTime(now.year + 1));
    expect(r.spentPaise, 3000);
  });

  test('monthly flow buckets money in and out per month', () async {
    final lastMonth = DateTime(now.year, now.month - 1, 12, 9);
    await repo.add(manual('a', 5000, at: lastMonth));
    await repo.add(manual('b', 7000));
    await repo.add(manual('c', 100000, type: TxnType.credit));
    final flow = await repo.monthlyFlow(DateTime(now.year, now.month));
    expect(flow, hasLength(6));
    expect(flow.last.month, DateTime(now.year, now.month));
    expect(flow.last.outPaise, 7000);
    expect(flow.last.inPaise, 100000);
    expect(flow[4].outPaise, 5000);
  });

  test('the same payment recorded twice is found as a duplicate', () async {
    await repo.add(manual('a', 12490, payee: 'Sri Krishna Stores'));
    await repo.add(manual('b', 12490, at: now.add(const Duration(minutes: 3))));
    await repo.add(manual('c', 5000, at: now.add(const Duration(minutes: 1))));
    final groups = await repo.duplicateGroups();
    expect(groups, hasLength(1));
    expect(groups.single.map((t) => t.id), unorderedEquals(['a', 'b']));
  });

  test('payments far apart, or with different bank references, are not duplicates', () async {
    await repo.add(manual('a', 2000));
    await repo.add(manual('b', 2000, at: now.add(const Duration(minutes: 30))));
    await repo.upsertDetected(payment('s1', source: 'sms', debit: true, ref: '111111111111', paise: 900), validIds);
    await repo.upsertDetected(
      payment('s2', source: 'sms', debit: true, ref: '222222222222', paise: 900, at: now.add(const Duration(minutes: 1))),
      validIds,
    );
    expect(await repo.duplicateGroups(), isEmpty);
  });

  test('the duplicate with a category is kept, and "Not duplicates" is remembered', () async {
    await repo.add(manual('a', 3000));
    await repo.add(manual('b', 3000, at: now.add(const Duration(minutes: 2))));
    await repo.setCategory((await repo.byId('b'))!, 'food');
    var groups = await repo.duplicateGroups();
    expect(TransactionRepository.keeperOf(groups.single).id, 'b');

    await repo.ignoreDuplicates(groups.single);
    expect(await repo.duplicateGroups(), isEmpty);

    await repo.add(manual('c', 4000));
    await repo.add(manual('d', 4000, at: now.add(const Duration(minutes: 1))));
    groups = await repo.duplicateGroups();
    expect(groups.single.map((t) => t.id), unorderedEquals(['c', 'd']));
    await repo.delete('d');
    expect(await repo.duplicateGroups(), isEmpty);
  });
}
