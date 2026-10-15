// Drives the real screens on a real (in-memory) SQLite database: the same
// taps a user makes, checked both on screen and in the saved data.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:expense_tracker/core/db/app_database.dart';
import 'package:expense_tracker/core/providers.dart';
import 'package:expense_tracker/core/theme/app_theme.dart';
import 'package:expense_tracker/features/detection/detection_service.dart';
import 'package:expense_tracker/features/home/app_shell.dart';
import 'package:expense_tracker/features/transactions/transaction_repository.dart';
import 'package:expense_tracker/features/transactions/txn.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late TransactionRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.createSchema(db);
    repo = TransactionRepository(db);
  });

  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(AppDatabase.wrap(db)),
        detectionStatusProvider.overrideWith((ref) async => DetectionStatus.unsupported),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const AppShell()),
    ));
    await settle(tester);
  }

  Future<void> openAdd(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
  }

  testWidgets('add an expense by hand: it is saved and shows on Home', (tester) async {
    await start(tester);
    await openAdd(tester);
    expect(find.text('New expense'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '120');
    await tester.enterText(find.byType(TextField).at(1), 'Tea shop');
    await tester.tap(find.text('Save'));
    await settle(tester);

    final saved = await repo.list();
    expect(saved, hasLength(1));
    expect(saved.single.amountPaise, 12000);
    expect(saved.single.payeeName, 'Tea shop');
    expect(saved.single.type, TxnType.debit);
    expect(saved.single.paymentMode, PaymentMode.cash);
    expect(find.text('New expense'), findsNothing, reason: 'back on Home');
    expect(find.text('₹120'), findsWidgets);
  });

  testWidgets('saving without an amount shows an error and saves nothing', (tester) async {
    await start(tester);
    await openAdd(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Enter an amount above ₹0'), findsOneWidget);
    expect(await repo.list(), isEmpty);
  });

  testWidgets('money received is saved as income', (tester) async {
    await start(tester);
    await openAdd(tester);
    await tester.tap(find.text('Received'));
    await settle(tester);
    expect(find.text('Money received'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '500');
    await tester.tap(find.text('UPI'));
    await tester.tap(find.text('Save'));
    await settle(tester);
    final t = (await repo.list()).single;
    expect(t.type, TxnType.credit);
    expect(t.paymentMode, PaymentMode.upi);
    expect((await repo.monthSummary(DateTime.now())).incomePaise, 50000);
  });

  testWidgets('choose a category while adding', (tester) async {
    await start(tester);
    await openAdd(tester);
    await tester.enterText(find.byType(TextField).at(0), '75');
    await tester.tap(find.text('Choose category').last);
    await settle(tester);
    await tester.tap(find.text('Groceries').last);
    await settle(tester);
    expect(find.text('Groceries'), findsWidgets);
    await tester.tap(find.text('Save'));
    await settle(tester);
    final t = (await repo.list()).single;
    expect(t.categoryId, 'groceries');
    expect(t.isReviewed, isTrue);
    expect(await repo.toCategorize(), isEmpty);
  });

  testWidgets('delete a transaction, then undo', (tester) async {
    final now = DateTime.now();
    await repo.add(Txn(
      id: 'x1',
      amountPaise: 9900,
      type: TxnType.debit,
      status: TxnStatus.success,
      source: TxnSource.manual,
      paymentMode: PaymentMode.cash,
      txnTime: now,
      createdAt: now,
      updatedAt: now,
      payeeName: 'Bus ticket',
    ));
    await start(tester);
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await settle(tester);
    await tester.tap(find.text('Bus ticket').last);
    await settle(tester);
    expect(find.text('Edit transaction'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await settle(tester);
    expect(await repo.list(), isEmpty);
    expect(find.text('Transaction deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await repo.list(), hasLength(1));
  });

  testWidgets('search finds a payment by amount; Money in filter hides spending', (tester) async {
    final now = DateTime.now();
    Txn t(String id, int paise, TxnType type, String name) => Txn(
          id: id,
          amountPaise: paise,
          type: type,
          status: TxnStatus.success,
          source: TxnSource.manual,
          paymentMode: PaymentMode.cash,
          txnTime: now,
          createdAt: now,
          updatedAt: now,
          payeeName: name,
        );
    await repo.add(t('a', 25000, TxnType.debit, 'Groceries run'));
    await repo.add(t('b', 100000, TxnType.credit, 'Salary part'));
    await start(tester);
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await settle(tester);

    await tester.enterText(find.byType(SearchBar), '250');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('Groceries run'), findsWidgets);
    expect(find.text('Salary part'), findsNothing);

    await tester.enterText(find.byType(SearchBar), '');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Money in'));
    await settle(tester);
    expect(find.text('Salary part'), findsWidgets);
    expect(find.text('Groceries run'), findsNothing);
  });

  testWidgets('Home can show the previous month', (tester) async {
    final now = DateTime.now();
    final last = DateTime(now.year, now.month - 1, 5, 10);
    await repo.add(Txn(
      id: 'old',
      amountPaise: 400000,
      type: TxnType.debit,
      status: TxnStatus.success,
      source: TxnSource.manual,
      paymentMode: PaymentMode.cash,
      txnTime: last,
      createdAt: last,
      updatedAt: last,
      payeeName: 'Rent last month',
    ));
    await start(tester);
    expect(find.text('₹4,000'), findsNothing, reason: 'this month has no spending');
    await tester.tap(find.byTooltip('Previous month'));
    await settle(tester);
    expect(find.text('₹4,000'), findsWidgets);
    await tester.tap(find.byTooltip('Next month'));
    await settle(tester);
    expect(find.text('₹4,000'), findsNothing);
  });
}
