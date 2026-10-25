import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/ui.dart';
import '../../core/utils/formatters.dart';
import 'add_transaction_screen.dart';
import 'delete_action.dart';
import 'transaction_repository.dart';
import 'transaction_tile.dart';
import 'txn.dart';

Future<void> openDuplicates(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DuplicatesScreen()),
    );

/// Payments that look like one payment recorded twice (same amount and
/// direction within 10 minutes). Delete the extras in one tap, or mark a
/// group as "Not duplicates".
class DuplicatesScreen extends ConsumerWidget {
  const DuplicatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(duplicatesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Possible duplicates')),
      body: groups.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Could not check for duplicates',
          message: '$e',
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.task_alt,
              title: 'No duplicates',
              message: 'Payments recorded twice will show up here.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 8),
                child: Text(
                  'Same amount, same direction, recorded within 10 minutes. '
                  'Keep one and delete the rest, or tap a payment to check it first.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              for (final g in list) _DuplicateGroup(group: g),
            ],
          );
        },
      ),
    );
  }
}

class _DuplicateGroup extends ConsumerWidget {
  const _DuplicateGroup({required this.group});

  final List<Txn> group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final categories = ref.watch(categoryMapProvider);
    final keeper = TransactionRepository.keeperOf(group);
    final extras = group.where((x) => x.id != keeper.id).map((x) => x.id).toList();
    final debit = group.first.type == TxnType.debit;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
            child: Text(
              '${debit ? 'Paid' : 'Received'} ${formatPaise(group.first.amountPaise)} · '
              'recorded ${group.length} times',
              style: t.titleSmall,
            ),
          ),
          Group(
            children: [
              for (final x in group)
                TransactionTile(
                  txn: x,
                  category: categories[x.categoryId],
                  showDate: true,
                  onTap: () => openTransactionEditor(context, existing: x),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 10, kGutter, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => deleteTransactionsWithUndo(
                    context,
                    ref,
                    extras,
                    message: extras.length == 1 ? 'Duplicate deleted' : '${extras.length} duplicates deleted',
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(extras.length == 1 ? 'Delete the extra one' : 'Delete ${extras.length} extras'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await ref.read(txnRepoProvider).ignoreDuplicates(group);
                    ref.invalidate(duplicatesProvider);
                  },
                  child: const Text('Not duplicates'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 0),
            child: Text(
              keeper.categoryId != null
                  ? 'Keeps the one that already has a category.'
                  : keeper.upiRef != null
                      ? 'Keeps the one with the bank reference.'
                      : 'Keeps the first one recorded.',
              style: t.bodySmall?.copyWith(color: p.muted),
            ),
          ),
        ],
      ),
    );
  }
}
