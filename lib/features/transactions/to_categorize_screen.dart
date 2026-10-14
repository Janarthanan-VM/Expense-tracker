import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/ui.dart';
import 'categorize_action.dart';
import 'transaction_tile.dart';

/// Every payment without a confirmed category, in one place.
class ToCategorizeScreen extends ConsumerWidget {
  const ToCategorizeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(toCategorizeProvider);
    final categories = ref.watch(categoryMapProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('To categorize')),
      body: pending.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Could not load payments',
          message: '$e',
        ),
        data: (list) {
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
                  list.length == 1
                      ? '1 payment. Tap it to choose a category.'
                      : '${list.length} payments. Tap one to choose its category; '
                          'suggested ones need just a tap to confirm.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Group(
                children: [
                  for (final t in list)
                    TransactionTile(
                      txn: t,
                      category: categories[t.categoryId],
                      showDate: true,
                      onTap: () => categorizeTransaction(context, ref, t),
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
