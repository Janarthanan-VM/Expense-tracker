import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/ui.dart';
import 'categorize_action.dart';
import 'delete_action.dart';
import 'duplicates_screen.dart';
import 'transaction_tile.dart';

/// Every payment without a confirmed category, in one place. Swipe a
/// payment left to delete it (a duplicate, or not really a payment).
class ToCategorizeScreen extends ConsumerStatefulWidget {
  const ToCategorizeScreen({super.key});

  @override
  ConsumerState<ToCategorizeScreen> createState() => _ToCategorizeScreenState();
}

class _ToCategorizeScreenState extends ConsumerState<ToCategorizeScreen> {
  /// Swiped away: hidden at once, before the list reloads.
  final _removed = <String>{};

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(toCategorizeProvider);
    final categories = ref.watch(categoryMapProvider);
    final duplicates = ref.watch(duplicatesProvider).valueOrNull ?? const [];
    final error = Theme.of(context).colorScheme.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('To categorize'),
        actions: [
          if (duplicates.isNotEmpty)
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DuplicatesScreen()),
              ),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: Text('${duplicates.length} duplicate${duplicates.length == 1 ? '' : 's'}'),
            ),
        ],
      ),
      body: pending.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Could not load payments',
          message: '$e',
        ),
        data: (all) {
          // Once the list has reloaded without them, forget swiped ids so an
          // Undo brings the payment back here.
          _removed.removeWhere((id) => !all.any((t) => t.id == id));
          final list = all.where((t) => !_removed.contains(t.id)).toList();
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.task_alt,
              title: 'All caught up',
              message: 'Every payment has a category. New ones will show up here.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 16),
                child: Text(
                  '${list.length == 1 ? '1 payment' : '${list.length} payments'}. '
                  'Tap one to choose its category. Swipe left to delete a duplicate.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Group(
                children: [
                  for (final t in list)
                    Dismissible(
                      key: ValueKey('cat-${t.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: error,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onError),
                      ),
                      onDismissed: (_) {
                        setState(() => _removed.add(t.id));
                        deleteTransactionsWithUndo(context, ref, [t.id]).then((_) {});
                      },
                      child: TransactionTile(
                        txn: t,
                        category: categories[t.categoryId],
                        showDate: true,
                        onTap: () => categorizeTransaction(context, ref, t),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
