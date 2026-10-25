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
    await tester.tap(find.byTooltip('Add an expense or money received by hand'));
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
    await settle(tester);
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
    // Let the edit screen finish closing before touching the snackbar.
    await settle(tester);
    expect(find.text('Transaction deleted'), findsOneWidget);

    final undo = find.widgetWithText(SnackBarAction, 'Undo');
    expect(undo, findsOneWidget, reason: 'one visible Undo button');
    await tester.tap(undo);
    await settle(tester);
    expect(find.text('Transaction deleted'), findsNothing, reason: 'the snackbar closes when Undo is pressed');
    await settle(tester);
    expect(await repo.list(), hasLength(1), reason: 'Undo brings the payment back');
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

  testWidgets('split a bill equally: only your share is spent, friends owe the rest', (tester) async {
    await start(tester);
    await openAdd(tester);
    await tester.enterText(find.byType(TextField).at(0), '1000');
    await tester.pump();
    await tester.tap(find.text('Split with friends'));
    await settle(tester);
    expect(find.text('Split ₹1,000'), findsOneWidget);
    await tester.tap(find.byTooltip('More people'));
    await tester.tap(find.byTooltip('More people'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.text('Your share ₹250'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);
    await settle(tester);

    final t = (await repo.list()).single;
    expect(t.amountPaise, 100000);
    expect(t.mySharePaise, 25000);
    expect((await repo.monthSummary(DateTime.now())).spentPaise, 25000);
    expect(await repo.owedToYou(), 75000);
    expect(find.text('₹250'), findsWidgets, reason: 'Home shows your share as spent');
  });

  testWidgets('create a new category from the picker while adding', (tester) async {
    await start(tester);
    await openAdd(tester);
    await tester.enterText(find.byType(TextField).at(0), '900');
    await tester.tap(find.text('Choose category').last);
    await settle(tester);
    await tester.tap(find.text('New category'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Gym');
    await tester.pump();
    await tester.tap(find.text('Create and use'));
    await settle(tester);
    expect(find.text('Gym'), findsWidgets, reason: 'the new category is selected');
    await tester.tap(find.text('Save'));
    await settle(tester);
    await settle(tester);
    final t = (await repo.list()).single;
    final cat = await db.query('categories', where: 'id = ?', whereArgs: [t.categoryId]);
    expect(cat.single['name'], 'Gym');
    expect(cat.single['kind'], 'expense');
  });

  testWidgets('Reports shows spending and money received for the month', (tester) async {
    final now = DateTime.now();
    Txn t(String id, int paise, TxnType type) => Txn(
          id: id,
          amountPaise: paise,
          type: type,
          status: TxnStatus.success,
          source: TxnSource.manual,
          paymentMode: PaymentMode.cash,
          txnTime: now,
          createdAt: now,
          updatedAt: now,
          payeeName: id,
          categoryId: type == TxnType.debit ? 'food' : 'salary',
          isReviewed: true,
        );
    await repo.add(t('Lunch', 25000, TxnType.debit));
    await repo.add(t('Pay', 1000000, TxnType.credit));
    await start(tester);
    await tester.tap(find.byIcon(Icons.pie_chart_outline));
    await settle(tester);
    expect(find.text('Where your money went'), findsOneWidget);
    expect(find.text('Food & dining'), findsWidgets);
    expect(find.text('₹250'), findsWidgets);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await settle(tester);
    expect(find.text('Where your money came from'), findsOneWidget);
    expect(find.text('Salary'), findsWidgets);
  });

  Txn detected(String id, int paise, DateTime at) => Txn(
        id: id,
        amountPaise: paise,
        type: TxnType.debit,
        status: TxnStatus.success,
        source: TxnSource.sms,
        paymentMode: PaymentMode.upi,
        txnTime: at,
        createdAt: at,
        updatedAt: at,
        payeeName: 'Chai Point',
      );

  testWidgets('a payment without a category can be deleted from the picker', (tester) async {
    await repo.add(detected('d1', 18000, DateTime.now()));
    await start(tester);
    await tester.ensureVisible(find.text('Payment needs a category'));
    await settle(tester);
    await tester.tap(find.text('Payment needs a category'));
    await settle(tester);
    await tester.tap(find.text('Chai Point').last);
    await settle(tester);
    await tester.tap(find.text('Delete this payment (duplicate or not mine)'));
    await settle(tester);
    expect(await repo.list(), isEmpty);
    expect(find.text('Payment deleted'), findsOneWidget);
    expect(find.text('All caught up'), findsOneWidget);
  });

  testWidgets('duplicates: delete the extra one in one tap', (tester) async {
    final now = DateTime.now();
    await repo.add(detected('d1', 18000, now));
    await repo.add(detected('d2', 18000, now.add(const Duration(minutes: 2))));
    await start(tester);
    expect(find.text('1 possible duplicate'), findsOneWidget);
    await tester.ensureVisible(find.text('1 possible duplicate'));
    await settle(tester);
    await tester.tap(find.text('1 possible duplicate'));
    await settle(tester);
    expect(find.text('Possible duplicates'), findsOneWidget);
    await tester.tap(find.text('Delete the extra one'));
    await settle(tester);
    final left = await repo.list();
    expect(left.map((t) => t.id), ['d1'], reason: 'keeps the first one recorded');
    expect(find.text('No duplicates'), findsOneWidget);
  });
}
