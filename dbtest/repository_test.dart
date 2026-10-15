// Runs the real repository code against SQLite on the build machine, to
// check that detected payments are saved and duplicates handled correctly.
// CI copies this to test_db/ and runs: flutter test test_db
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
}
