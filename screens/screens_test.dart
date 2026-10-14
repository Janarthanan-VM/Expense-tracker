// Renders the main screens with sample data to PNG files, so the design can
// be reviewed without a phone. Run by CI with:
//   flutter test test_screens --update-goldens
// Images are written to test_screens/out/.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/core/providers.dart';
import 'package:expense_tracker/core/theme/app_theme.dart';
import 'package:expense_tracker/features/categories/default_categories.dart';
import 'package:expense_tracker/features/detection/detection_service.dart';
import 'package:expense_tracker/features/home/app_shell.dart';
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

Widget _app({required ThemeMode mode}) => ProviderScope(
      overrides: [
        categoriesProvider.overrideWith((ref) async => defaultCategories),
        recentTxnsProvider.overrideWith((ref) async => _txns.take(5).toList()),
        toCategorizeProvider.overrideWith(
          (ref) async => _txns.where((t) => t.needsCategory).toList(),
        ),
        monthSummaryProvider.overrideWith((ref) async => _summary()),
        dailySpendProvider.overrideWith((ref) async => _daily()),
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
  setUpAll(_loadFonts);

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
    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);
    await _shot('4-add');
  });

  testWidgets('category picker', (tester) async {
    await start(tester, ThemeMode.light);
    await tester.longPress(find.text('Chai Point').first);
    await _settle(tester);
    await _shot('5-picker');
  });

  testWidgets('categories', (tester) async {
    await start(tester, ThemeMode.light);
    await tester.tap(find.byIcon(Icons.donut_large_outlined));
    await _settle(tester);
    await _shot('6-categories');
  });

  testWidgets('settings dark', (tester) async {
    await start(tester, ThemeMode.dark);
    await tester.tap(find.byIcon(Icons.tune_outlined));
    await _settle(tester);
    await _shot('7-settings-dark');
  });
}
