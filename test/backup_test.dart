import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:expense_tracker/core/db/app_database.dart';
import 'package:expense_tracker/features/backup/backup_codec.dart';
import 'package:expense_tracker/features/backup/backup_service.dart';
import 'package:expense_tracker/features/categories/default_categories.dart';
import 'package:expense_tracker/features/transactions/transaction_repository.dart';
import 'package:expense_tracker/features/transactions/txn.dart';

Future<Database> _freshDb() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('PRAGMA foreign_keys = ON');
  await AppDatabase.createSchema(db);
  return db;
}

Txn _txn(String id, int paise, {String? payee, String? category, String? note}) {
  final now = DateTime(2026, 10, 15, 9, 30);
  return Txn(
    id: id,
    amountPaise: paise,
    type: TxnType.debit,
    status: TxnStatus.success,
    source: TxnSource.manual,
    paymentMode: PaymentMode.cash,
    txnTime: now,
    createdAt: now,
    updatedAt: now,
    payeeName: payee,
    categoryId: category,
    note: note,
  );
}

void main() {
  sqfliteFfiInit();

  group('backup file', () {
    test('round-trips with the right password', () async {
      final data = {'app': 'Dripless', 'schemaVersion': 4, 'hello': 'नमस्ते ₹'};
      final bytes = await BackupCodec.encode(data, 'secret123');
      expect(utf8.decode(bytes).startsWith(BackupCodec.magic), isTrue);
      expect(utf8.decode(bytes).contains('नमस्ते'), isFalse, reason: 'contents are encrypted');
      final back = await BackupCodec.decode(bytes, 'secret123');
      expect(back['hello'], 'नमस्ते ₹');
    });

    test('a wrong password is rejected with a clear message', () async {
      final bytes = await BackupCodec.encode({'app': 'Dripless'}, 'secret123');
      expect(
        () => BackupCodec.decode(bytes, 'wrongpass'),
        throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('Wrong password'))),
      );
    });

    test('a file that is not a backup is rejected', () async {
      expect(
        () => BackupCodec.decode(Uint8List.fromList(utf8.encode('hello')), 'secret123'),
        throwsA(isA<BackupException>()),
      );
    });

    test('a short password is refused', () {
      expect(() => BackupCodec.encode({}, '123'), throwsA(isA<BackupException>()));
    });
  });

  group('backup and restore', () {
    test('restoring a backup brings back everything, replacing current data', () async {
      final source = await _freshDb();
      final repo = TransactionRepository(source);
      await repo.add(_txn('a', 25000, payee: 'Tea shop', category: 'food'));
      await repo.add(_txn('b', 9900, payee: 'Bus'));
      await repo.delete('b');
      await source.update('categories', {'name': 'Eating out'}, where: 'id = ?', whereArgs: ['food']);

      final file = await BackupCodec.encode(await BackupService(source).snapshot(), 'pass1234');

      final target = await _freshDb();
      final targetRepo = TransactionRepository(target);
      await targetRepo.add(_txn('old', 100, payee: 'Will be replaced'));

      final data = await BackupCodec.decode(file, 'pass1234');
      final restored = await BackupService(target).restore(data);
      expect(restored, 1, reason: 'one live payment; the deleted one is kept hidden');

      final list = await targetRepo.list();
      expect(list.map((t) => t.id), ['a']);
      final cats = await target.query('categories', where: 'id = ?', whereArgs: ['food']);
      expect(cats.single['name'], 'Eating out');
      final deleted = await targetRepo.byId('b', includeDeleted: true);
      expect(deleted?.deletedAt, isNotNull, reason: 'deleted payments stay deleted');
    });

    test('a backup from a newer app version is refused and changes nothing', () async {
      final db = await _freshDb();
      final repo = TransactionRepository(db);
      await repo.add(_txn('keep', 100));
      expect(
        () => BackupService(db).restore({'app': 'Dripless', 'schemaVersion': 999, 'categories': []}),
        throwsA(isA<BackupException>()),
      );
      expect(await repo.list(), hasLength(1));
    });

    test('last backup time is remembered', () async {
      final db = await _freshDb();
      final service = BackupService(db);
      expect(await service.lastBackup(), isNull);
      await service.markBackedUp();
      expect(await service.lastBackup(), isNotNull);
    });
  });

  group('spreadsheet export', () {
    test('has a header and one row per payment, safely quoted', () {
      final categories = {for (final c in defaultCategories) c.id: c};
      final csv = BackupService.toCsv([
        _txn('a', 25050, payee: 'Sri "Krishna" Stores', category: 'groceries', note: 'milk, bread'),
        _txn('b', 100, payee: '=HYPERLINK("x")'),
      ], categories);
      final lines = const LineSplitter().convert(csv);
      expect(lines, hasLength(3));
      expect(lines[0], startsWith('"Date","Time","Type","Amount (INR)"'));
      expect(lines[1], contains('"250.50"'));
      expect(lines[1], contains('"Sri ""Krishna"" Stores"'));
      expect(lines[1], contains('"milk, bread"'));
      expect(lines[1], contains('"Groceries"'));
      expect(lines[2], contains("\"'=HYPERLINK"), reason: 'formulas are not run by spreadsheets');
    });
  });
}
