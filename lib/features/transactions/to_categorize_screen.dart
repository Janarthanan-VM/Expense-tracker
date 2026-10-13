import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load payments: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'All payments have a category. New ones will appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: list.length + 1,
            separatorBuilder: (context, index) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Text(
                    'Tap a payment to choose its category. Suggested ones only need a tap to confirm.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }
              final t = list[i - 1];
              return TransactionTile(
                txn: t,
                category: categories[t.categoryId],
                showDate: true,
                onTap: () => categorizeTransaction(context, ref, t),
              );
            },
          );
        },
      ),
    );
  }
}
