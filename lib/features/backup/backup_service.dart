import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/db/app_database.dart';
import '../categories/category.dart';
import '../transactions/txn.dart';
import 'backup_codec.dart';

/// Reads everything into a backup, writes a backup back, and exports a
/// spreadsheet. All database work for backups lives here.
class BackupService {
  BackupService(this._db);

  final Database _db;

  /// Tables in an order that respects foreign keys when inserting.
  static const List<String> tables = ['categories', 'payees', 'transactions', 'transaction_splits'];

  static const String _lastBackupKey = 'last_backup_at';

  /// Every row of every table, including deleted payments (so a restored
  /// phone still knows not to capture them again).
  Future<Map<String, Object?>> snapshot() async {
    final data = <String, Object?>{
      'app': 'Dripless',
      'schemaVersion': AppDatabase.schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
    };
    for (final table in tables) {
      data[table] = await _db.query(table);
    }
    return data;
  }

  /// Replaces all data with [data] from a backup, in one transaction: if
  /// anything fails, nothing changes. Returns the number of transactions.
  Future<int> restore(Map<String, Object?> data) async {
    final version = (data['schemaVersion'] as num?)?.toInt();
    if (data['app'] != 'Dripless' || version == null) {
      throw const BackupException('This is not a Dripless backup file.');
    }
    if (version > AppDatabase.schemaVersion) {
      throw const BackupException(
        'This backup is from a newer version of Dripless. Update the app, then restore.',
      );
    }

    List<Map<String, Object?>> rows(String table) {
      final raw = data[table];
      if (raw == null) return const [];
      if (raw is! List) throw const BackupException('The backup file is damaged.');
      return [for (final r in raw) Map<String, Object?>.from(r as Map)];
    }

    final incoming = {for (final t in tables) t: rows(t)};
    if (incoming['categories']!.isEmpty) {
      throw const BackupException('The backup file is damaged.');
    }

    // Only copy columns this version knows, so older backups still restore.
    final columns = <String, Set<String>>{};
    for (final table in tables) {
      final info = await _db.rawQuery('PRAGMA table_info($table)');
      columns[table] = {for (final c in info) c['name']! as String};
    }

    await _db.transaction((t) async {
      for (final table in tables.reversed) {
        await t.delete(table);
      }
      for (final table in tables) {
        final known = columns[table]!;
        final batch = t.batch();
        for (final row in incoming[table]!) {
          batch.insert(table, {
            for (final e in row.entries)
              if (known.contains(e.key)) e.key: e.value,
          });
        }
        await batch.commit(noResult: true);
      }
    });
    return incoming['transactions']!.where((r) => r['deleted_at'] == null).length;
  }

  Future<void> markBackedUp() => _db.insert(
        'meta',
        {'key': _lastBackupKey, 'value': DateTime.now().millisecondsSinceEpoch.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<DateTime?> lastBackup() async {
    final rows = await _db.query('meta', where: 'key = ?', whereArgs: [_lastBackupKey]);
    if (rows.isEmpty) return null;
    final ms = int.tryParse(rows.first['value']! as String);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// All payments (not deleted) as a spreadsheet, oldest first.
  static String toCsv(List<Txn> txns, Map<String, TxnCategory> categories) {
    String cell(Object? v) {
      final s = v?.toString() ?? '';
      // Quote everything that could break a column; double inner quotes.
      // A leading = + - @ is prefixed so spreadsheets never run it as a formula.
      final safe = RegExp(r'^[=+\-@]').hasMatch(s) ? "'$s" : s;
      return '"${safe.replaceAll('"', '""')}"';
    }

    String two(int n) => n.toString().padLeft(2, '0');
    final out = StringBuffer()
      ..writeln([
        'Date', 'Time', 'Type', 'Amount (INR)', 'Name', 'UPI ID', 'Category',
        'Paid with', 'Note', 'UPI reference', 'Recorded from', 'Status',
      ].map(cell).join(','));
    final sorted = [...txns]..sort((a, b) => a.txnTime.compareTo(b.txnTime));
    for (final t in sorted) {
      final d = t.txnTime;
      out.writeln([
        '${d.year}-${two(d.month)}-${two(d.day)}',
        '${two(d.hour)}:${two(d.minute)}',
        t.type == TxnType.debit ? 'Money out' : 'Money in',
        (t.amountPaise / 100).toStringAsFixed(2),
        t.payeeName,
        t.payeeVpa,
        categories[t.categoryId]?.name ?? '',
        t.paymentMode.label,
        t.note,
        t.upiRef,
        switch (t.source) {
          TxnSource.manual => 'Added by hand',
          TxnSource.scanPay => 'Scan & Pay',
          TxnSource.notification => 'App notification',
          TxnSource.sms => 'Bank SMS',
          TxnSource.ocr => 'Screenshot',
          TxnSource.statement => 'Statement',
        },
        switch (t.status) {
          TxnStatus.success => 'Done',
          TxnStatus.pending => 'Waiting',
          TxnStatus.failed => 'Failed',
        },
      ].map(cell).join(','));
    }
    return out.toString();
  }
}
