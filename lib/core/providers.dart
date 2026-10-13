import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/categories/category.dart';
import '../features/categories/category_repository.dart';
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

/// Transaction list, filtered by the search text.
final txnListProvider = FutureProvider.autoDispose.family<List<Txn>, String>(
  (ref, search) => ref.watch(txnRepoProvider).list(search: search),
);

/// Call after any change to transactions or categories so every screen updates.
void refreshAll(WidgetRef ref) {
  ref.invalidate(categoriesProvider);
  ref.invalidate(recentTxnsProvider);
  ref.invalidate(toCategorizeProvider);
  ref.invalidate(monthSummaryProvider);
  ref.invalidate(txnListProvider);
}
