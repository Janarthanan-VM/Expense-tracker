import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../features/categories/default_categories.dart';
import 'db_key_store.dart';

/// Encrypted SQLite database (SQLCipher) stored only on the phone.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const int schemaVersion = 5;
  static const String fileName = 'expense_tracker.db';

  static Future<AppDatabase> open() async {
    final password = await DbKeyStore().getOrCreateKey();
    final path = p.join(await getDatabasesPath(), fileName);

    final db = await openDatabase(
      path,
      password: password,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) => createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _migrateToV2(db);
        if (oldVersion < 3) await _migrateToV3(db);
        if (oldVersion < 4) await _migrateToV4(db);
        if (oldVersion < 5) await _migrateToV5(db);
      },
    );
    return AppDatabase._(db);
  }

  /// Creates every table at the latest version and adds default categories.
  /// Public so tests can build the same schema on a plain SQLite database.
  static Future<void> createSchema(Database db) async {
    await _createSchemaV1(db);
    await _migrateToV2(db);
    await _migrateToV3(db);
    await _migrateToV4(db);
    await _seedDefaultCategories(db);
    await _migrateToV5(db);
  }

  static Future<void> _createSchemaV1(Database db) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE categories (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        icon_key    TEXT NOT NULL,
        color       INTEGER NOT NULL,
        kind        TEXT NOT NULL CHECK (kind IN ('expense', 'income', 'transfer')),
        parent_id   TEXT REFERENCES categories(id),
        is_default  INTEGER NOT NULL DEFAULT 0,
        is_hidden   INTEGER NOT NULL DEFAULT 0,
        sort_order  INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Payees the user asked us to remember ("Always use this category").
    // match_key is "<debit|credit>|vpa:<upi id>", or "...|name:<payee name>" without a UPI ID.
    batch.execute('''
      CREATE TABLE payees (
        id                   TEXT PRIMARY KEY,
        match_key            TEXT NOT NULL UNIQUE,
        display_name         TEXT,
        vpa                  TEXT,
        default_category_id  TEXT REFERENCES categories(id) ON DELETE SET NULL,
        updated_at           INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE transactions (
        id               TEXT PRIMARY KEY,
        amount_paise     INTEGER NOT NULL CHECK (amount_paise > 0),
        type             TEXT NOT NULL,
        status           TEXT NOT NULL,
        category_id      TEXT REFERENCES categories(id) ON DELETE SET NULL,
        category_source  TEXT,
        is_reviewed      INTEGER NOT NULL DEFAULT 0,
        payee_name       TEXT,
        payee_vpa        TEXT,
        upi_ref          TEXT,
        upi_app          TEXT,
        source           TEXT NOT NULL,
        note             TEXT,
        txn_time         INTEGER NOT NULL,
        created_at       INTEGER NOT NULL,
        updated_at       INTEGER NOT NULL,
        deleted_at       INTEGER
      )
    ''');

    // The same UPI payment from Scan & Pay, notification and SMS is stored once.
    batch.execute('''
      CREATE UNIQUE INDEX idx_txn_upi_ref ON transactions(upi_ref)
      WHERE upi_ref IS NOT NULL AND deleted_at IS NULL
    ''');
    batch.execute('CREATE INDEX idx_txn_time ON transactions(txn_time)');
    batch.execute('CREATE INDEX idx_txn_category ON transactions(category_id)');

    // Split one payment across categories (screen comes in a later step).
    batch.execute('''
      CREATE TABLE transaction_splits (
        id              TEXT PRIMARY KEY,
        transaction_id  TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
        category_id     TEXT NOT NULL REFERENCES categories(id),
        amount_paise    INTEGER NOT NULL CHECK (amount_paise > 0),
        note            TEXT
      )
    ''');

    await batch.commit(noResult: true);
  }

  /// v2: payee rules are stored per direction ("debit|vpa:..." /
  /// "credit|vpa:..."). Existing rules get the direction of their category.
  static Future<void> _migrateToV2(Database db) async {
    await db.execute('''
      UPDATE payees SET match_key =
        CASE WHEN (SELECT kind FROM categories WHERE id = payees.default_category_id) = 'income'
             THEN 'credit|' ELSE 'debit|' END || match_key
      WHERE match_key NOT LIKE 'debit|%' AND match_key NOT LIKE 'credit|%'
    ''');
  }

  /// v3: how each payment was made (cash, upi, card, bank, other).
  /// Earlier manual entries become cash; captured ones (Scan & Pay,
  /// notification, SMS) are UPI.
  static Future<void> _migrateToV3(Database db) async {
    await db.execute(
      "ALTER TABLE transactions ADD COLUMN payment_mode TEXT NOT NULL DEFAULT 'other'",
    );
    await db.execute('''
      UPDATE transactions SET payment_mode =
        CASE WHEN source = 'manual' THEN 'cash'
             WHEN source IN ('scanPay', 'notification', 'sms') THEN 'upi'
             ELSE 'other' END
    ''');
    await db.execute(
      'CREATE INDEX idx_txn_payment_mode ON transactions(payment_mode)',
    );
  }

  /// v4: small key/value settings stored with the data (last backup time).
  static Future<void> _migrateToV4(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  /// v5: split bills. "my_share_paise" is your part of a shared bill, and
  /// the "Paid back by friends" category marks money friends return.
  static Future<void> _migrateToV5(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(transactions)');
    if (!cols.any((c) => c['name'] == 'my_share_paise')) {
      await db.execute('ALTER TABLE transactions ADD COLUMN my_share_paise INTEGER');
    }
    final settlement = defaultCategories.firstWhere((c) => c.id == splitSettlementId);
    await db.insert('categories', settlement.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Opens an already-created database, for tests.
  static AppDatabase wrap(Database db) => AppDatabase._(db);

  static Future<void> _seedDefaultCategories(Database db) async {
    final batch = db.batch();
    for (final category in defaultCategories) {
      batch.insert('categories', category.toMap());
    }
    await batch.commit(noResult: true);
  }
}
