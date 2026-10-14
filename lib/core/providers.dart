import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/categories/category.dart';
import '../features/categories/category_repository.dart';
import '../features/detection/detection_service.dart';
import '../features/detection/detection_sync.dart';
import '../features/transactions/transaction_repository.dart';
import '../features/transactions/txn.dart';
import 'db/app_database.dart';

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

final monthSummaryProvider = FutureProvider<MonthSummary>(
  (ref) => ref.watch(txnRepoProvider).monthSummary(DateTime.now()),
);

/// This month's spending per day, for the bars on Home.
final dailySpendProvider = FutureProvider<List<int>>(
  (ref) => ref.watch(txnRepoProvider).dailySpend(DateTime.now()),
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
void refreshAll(WidgetRef ref) {
  ref.invalidate(categoriesProvider);
  ref.invalidate(recentTxnsProvider);
  ref.invalidate(toCategorizeProvider);
  ref.invalidate(monthSummaryProvider);
  ref.invalidate(dailySpendProvider);
  ref.invalidate(txnListProvider);
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
