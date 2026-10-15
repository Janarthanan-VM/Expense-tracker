// Renders the main screens with sample data to PNG files, so the design can
// be reviewed without a phone. Run by CI with:
//   flutter test test_screens --update-goldens
// Images are written to test_screens/out/.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:expense_tracker/core/db/app_database.dart';
import 'package:expense_tracker/core/providers.dart';
import 'package:expense_tracker/features/backup/backup_screen.dart';
import 'package:expense_tracker/features/scanpay/scan_pay_screen.dart';
import 'package:expense_tracker/core/theme/app_theme.dart';
import 'package:expense_tracker/features/categories/default_categories.dart';
import 'package:expense_tracker/features/detection/detection_service.dart';
import 'package:expense_tracker/features/home/app_shell.dart';
import 'package:expense_tracker/features/reports/report_data.dart';
import 'package:expense_tracker/features/transactions/txn.dart';

Future<void> _loadFonts() async {
  ByteData bytes(String path) => ByteData.sublistView(File(path).readAsBytesSync());
  final manrope = FontLoader('Manrope');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    manrope.addFont(Future.value(bytes('assets/fonts/Manrope-$w.ttf')));
  }
  await manrope.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(bytes('test_screens/MaterialIcons-Regular.otf')));
  await icons.load();
}

final _now = DateTime.now();
DateTime _ago({int days = 0, int hours = 0, int minutes = 0}) {
  final today = DateTime(_now.year, _now.month, _now.day, 21, 30);
  return today.subtract(Duration(days: days, hours: hours, minutes: minutes));
}

Txn _txn(
  String id,
  int rupees,
  DateTime at, {
  bool debit = true,
  String? category,
  bool reviewed = true,
  String? payee,
  PaymentMode mode = PaymentMode.upi,
  TxnSource source = TxnSource.sms,
}) =>
    Txn(
      id: id,
      amountPaise: rupees * 100,
      type: debit ? TxnType.debit : TxnType.credit,
      status: TxnStatus.success,
      source: source,
      paymentMode: mode,
      txnTime: at,
      createdAt: at,
      updatedAt: at,
      categoryId: category,
      categorySource: category == null ? null : CategorySource.user,
      isReviewed: category != null && reviewed,
      payeeName: payee,
    );

final _txns = <Txn>[
  _txn('1', 180, _ago(hours: 1), payee: 'Chai Point'),
  _txn('2', 1249, _ago(hours: 3), category: 'groceries', reviewed: false, payee: 'Sri Krishna Stores'),
  _txn('3', 60, _ago(hours: 5), category: 'transport', payee: 'Auto', mode: PaymentMode.cash, source: TxnSource.manual),
  _txn('4', 45000, _ago(days: 1, hours: 2), debit: false, category: 'salary', payee: 'Acme Pvt Ltd', mode: PaymentMode.bank),
  _txn('5', 899, _ago(days: 1, hours: 6), category: 'food', payee: 'Swiggy', mode: PaymentMode.card),
  _txn('6', 349, _ago(days: 2, hours: 1), category: 'bills', payee: 'Jio Recharge'),
  _txn('7', 2000, _ago(days: 2, hours: 4), category: 'family', payee: 'Ravi Kumar'),
  _txn('8', 500, _ago(days: 3), debit: false, category: 'received', payee: 'Priya'),
];

List<int> _daily() {
  final days = DateTime(_now.year, _now.month + 1, 0).day;
  const pattern = [420, 180, 1250, 0, 640, 2300, 310, 90, 760, 0, 1480, 520, 3100, 240, 680, 1290];
  return [
    for (var d = 1; d <= days; d++) d > _now.day ? 0 : pattern[d % pattern.length],
  ];
}

MonthSummary _summary() => MonthSummary(
      month: DateTime(_now.year, _now.month),
      spentPaise: 1245000,
      incomePaise: 4550000,
      byCategory: const [
        CategoryTotal(categoryId: 'rent', totalPaise: 600000),
        CategoryTotal(categoryId: 'food', totalPaise: 241000),
        CategoryTotal(categoryId: 'groceries', totalPaise: 186000),
        CategoryTotal(categoryId: null, totalPaise: 98000),
        CategoryTotal(categoryId: 'transport', totalPaise: 64000),
        CategoryTotal(categoryId: 'bills', totalPaise: 34900),
        CategoryTotal(categoryId: 'shopping', totalPaise: 21100),
      ],
      spentByMode: const {
        PaymentMode.upi: 1032000,
        PaymentMode.cash: 54000,
        PaymentMode.card: 159000,
      },
    );

late Database _db;

PeriodReport _report() => PeriodReport(
      start: DateTime(_now.year, _now.month),
      end: DateTime(_now.year, _now.month + 1),
      spentPaise: 1245000,
      incomePaise: 4500000,
      paidBackPaise: 50000,
      spending: const [
        Slice(categoryId: 'rent', paise: 600000),
        Slice(categoryId: 'food', paise: 241000),
        Slice(categoryId: 'groceries', paise: 186000),
        Slice(categoryId: null, paise: 98000),
        Slice(categoryId: 'transport', paise: 64000),
        Slice(categoryId: 'bills', paise: 34900),
        Slice(categoryId: 'shopping', paise: 21100),
      ],
      receiving: const [
        Slice(categoryId: 'salary', paise: 4500000),
        Slice(categoryId: 'split_settlement', paise: 50000),
      ],
      topPayees: const [
        PayeeTotal(name: 'Landlord', paise: 600000, count: 1),
        PayeeTotal(name: 'Swiggy', paise: 180000, count: 6),
        PayeeTotal(name: 'Sri Krishna Stores', paise: 124900, count: 3),
      ],
    );

List<MonthFlow> _flow() => [
      for (var i = 5; i >= 0; i--)
        MonthFlow(
          month: DateTime(_now.year, _now.month - i),
          outPaise: [980000, 1120000, 1410000, 1030000, 1310000, 1245000][5 - i],
          inPaise: [4500000, 4500000, 4650000, 4500000, 4500000, 4550000][5 - i],
        ),
    ];

Widget _app({required ThemeMode mode}) => ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(AppDatabase.wrap(_db)),
        lastBackupProvider.overrideWith((ref) async => null),
        categoriesProvider.overrideWith((ref) async => defaultCategories),
        recentTxnsProvider.overrideWith((ref) async => _txns.take(5).toList()),
        toCategorizeProvider.overrideWith(
          (ref) async => _txns.where((t) => t.needsCategory).toList(),
        ),
        monthSummaryProvider.overrideWith((ref) async => _summary()),
        dailySpendProvider.overrideWith((ref) async => _daily()),
        reportProvider.overrideWith((ref) async => _report()),
        monthlyFlowProvider.overrideWith((ref) async => _flow()),
        txnListProvider.overrideWith((ref, filter) async => _txns),
        detectionStatusProvider.overrideWith((ref) async => DetectionStatus.unsupported),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: const AppShell(),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _shot(String name) => expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('out/$name.png'),
    );

void main() {
  setUpAll(() async {
    await _loadFonts();
    sqfliteFfiInit();
    _db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.createSchema(_db);
  });

  Future<void> start(WidgetTester tester, ThemeMode mode) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(mode: mode));
    await _settle(tester);
  }

  testWidgets('home light', (tester) async {
    await start(tester, ThemeMode.light);
    await _shot('1-home-light');
  });

  testWidgets('home dark', (tester) async {
    await start(tester, ThemeMode.dark);
    await _shot('2-home-dark');
  });

  testWidgets('transactions', (tester) async {
    await start(tester, ThemeMode.light);
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await _settle(tester);
    await _shot('3-transactions');
  });

  testWidgets('add', (tester) async {
    await start(tester, ThemeMode.light);
    await tester.tap(find.byTooltip('Add an expense or money received by hand'));
    await _settle(tester);
    await _shot('4-add');
  });

  testWidgets('category picker', (tester) async {
    await start(tester, ThemeMode.light);
    await tester.tap(find.byTooltip('Add an expense or money received by hand'));
    await _settle(tester);
    await tester.tap(find.text('Choose category').last);
    await _settle(tester);
    await _shot('5-picker');
  });

  testWidgets('categories', (tester) async {
    await start(tester, ThemeMode.light);
    await tester.tap(find.byIcon(Icons.category_outlined));
    await _settle(tester);
    await _shot('6-categories');
  });

  testWidgets('settings dark', (tester) async {
    await start(tester, ThemeMode.dark);
    await tester.tap(find.byIcon(Icons.tune_outlined));
    await _settle(tester);
    await _shot('7-settings-dark');
  });

  testWidgets('scan and pay', (tester) async {
    await start(tester, ThemeMode.light);
    Navigator.of(tester.element(find.byType(AppShell))).push(MaterialPageRoute(
      builder: (_) => const ScanPayScreen(
        initialQr: 'upi://pay?pa=sristores@okaxis&pn=Sri%20Krishna%20Stores&mc=5411',
      ),
    ));
    await _settle(tester);
    await _shot('8-scan-pay');
  });

  testWidgets('backup', (tester) async {
    await start(tester, ThemeMode.light);
    Navigator.of(tester.element(find.byType(AppShell))).push(
      MaterialPageRoute(builder: (_) => const BackupScreen()),
    );
    await _settle(tester);
    await _shot('9-backup');
  });

  testWidgets('reports light', (tester) async {
    await start(tester, ThemeMode.light);
    await tester.tap(find.byIcon(Icons.pie_chart_outline));
    await _settle(tester);
    await _shot('10-reports');
  });

  testWidgets('reports dark, scrolled', (tester) async {
    await start(tester, ThemeMode.dark);
    await tester.tap(find.byIcon(Icons.pie_chart_outline));
    await _settle(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await _settle(tester);
    await _shot('11-reports-dark');
  });
}
