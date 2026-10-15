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
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
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
}
