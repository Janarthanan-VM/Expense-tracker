import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/backup/backup_service.dart';
import '../features/categories/category.dart';
import '../features/categories/category_repository.dart';
import '../features/detection/detection_service.dart';
import '../features/detection/detection_sync.dart';
import '../features/reports/report_data.dart';
import '../features/transactions/transaction_repository.dart';
import '../features/transactions/txn.dart';
import 'db/app_database.dart';
import 'platform_actions.dart';

/// Overridden in main() with the opened database.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final categoryRepoProvider =
    Provider((ref) => CategoryRepository(ref.watch(databaseProvider).db));

final txnRepoProvider =
    Provider((ref) => TransactionRepository(ref.watch(databaseProvider).db));

// ------------------------------------------------------------------ categories

final categoriesProvider = FutureProvider<List<TxnCategory>>(
  (ref) => ref.watch(categoryRepoProvider).all(),
);

/// id -> TxnCategory, for quick lookups when drawing transactions.
final categoryMapProvider = Provider<Map<String, TxnCategory>>((ref) {
  final list = ref.watch(categoriesProvider).valueOrNull ?? const <TxnCategory>[];
  return {for (final c in list) c.id: c};
});

// ---------------------------------------------------------------- transactions

final recentTxnsProvider =
    FutureProvider<List<Txn>>((ref) => ref.watch(txnRepoProvider).recent());

final toCategorizeProvider =
    FutureProvider<List<Txn>>((ref) => ref.watch(txnRepoProvider).toCategorize());

/// The month shown on Home (first day of that month). Starts at this month.
final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

final monthSummaryProvider = FutureProvider<MonthSummary>(
  (ref) => ref.watch(txnRepoProvider).monthSummary(ref.watch(selectedMonthProvider)),
);

/// Spending per day of the selected month, for the bars on Home.
final dailySpendProvider = FutureProvider<List<int>>(
  (ref) => ref.watch(txnRepoProvider).dailySpend(ref.watch(selectedMonthProvider)),
);

/// The period shown on the Reports screen. Starts at this month.
final reportRangeProvider = StateProvider<ReportRange>((ref) {
  final now = DateTime.now();
  return ReportRange(anchor: DateTime(now.year, now.month), year: false);
});

final reportProvider = FutureProvider<PeriodReport>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref.watch(txnRepoProvider).report(range.start, range.end);
});

/// Month bars: the 12 months of the year, or the 6 months up to the month.
final monthlyFlowProvider = FutureProvider<List<MonthFlow>>((ref) {
  final range = ref.watch(reportRangeProvider);
  return range.year
      ? ref.watch(txnRepoProvider).monthlyFlow(DateTime(range.anchor.year, 12), months: 12)
      : ref.watch(txnRepoProvider).monthlyFlow(range.anchor);
});

/// What friends still owe you for split bills.
final owedToYouProvider = FutureProvider<int>((ref) => ref.watch(txnRepoProvider).owedToYou());

/// "Always use for ..." rules, for Settings.
final payeeRulesProvider = FutureProvider<List<PayeeRule>>(
  (ref) => ref.watch(txnRepoProvider).payeeRules(),
);

/// Filters for the transaction list. A record, so equal filters share a cache.
/// [type]: null = all, debit = money out, credit = money in.
typedef TxnFilter = ({String search, PaymentMode? mode, TxnType? type});

/// Transaction list, filtered by search text, payment method and direction.
final txnListProvider = FutureProvider.autoDispose.family<List<Txn>, TxnFilter>(
  (ref, filter) => ref
      .watch(txnRepoProvider)
      .list(search: filter.search, mode: filter.mode, type: filter.type),
);

/// Call after any change to transactions or categories so every screen updates.
void refreshAll(WidgetRef ref) => invalidateData(ref.invalidate);

/// Same as [refreshAll], usable after the calling widget is gone (for
/// example from a snackbar's Undo button) via a ProviderContainer.
void invalidateData(void Function(ProviderOrFamily provider) invalidate) {
  for (final provider in <ProviderOrFamily>[
    categoriesProvider,
    recentTxnsProvider,
    toCategorizeProvider,
    monthSummaryProvider,
    dailySpendProvider,
    payeeRulesProvider,
    owedToYouProvider,
    reportProvider,
    monthlyFlowProvider,
    txnListProvider,
  ]) {
    invalidate(provider);
  }
}

// ---------------------------------------------------------- automatic detection

final detectionServiceProvider = Provider((ref) => DetectionService());

final detectionSyncProvider = Provider(
  (ref) => DetectionSync(
    ref.watch(detectionServiceProvider),
    ref.watch(txnRepoProvider),
    ref.watch(categoryRepoProvider),
  ),
);

final detectionStatusProvider = FutureProvider<DetectionStatus>(
  (ref) => ref.watch(detectionServiceProvider).status(),
);

// ---------------------------------------------------------------- backup, files

final platformActionsProvider = Provider((ref) => const PlatformActions());

final backupServiceProvider =
    Provider((ref) => BackupService(ref.watch(databaseProvider).db));

final lastBackupProvider = FutureProvider<DateTime?>(
  (ref) => ref.watch(backupServiceProvider).lastBackup(),
);
