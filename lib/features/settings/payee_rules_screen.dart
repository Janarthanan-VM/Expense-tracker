import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/ui.dart';

/// Every "Always use this category for ..." rule, with a way to remove one.
class PayeeRulesScreen extends ConsumerWidget {
  const PayeeRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(payeeRulesProvider);
    final categories = ref.watch(categoryMapProvider);
    final p = context.palette;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Remembered payees')),
      body: rules.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (e, _) => EmptyState(icon: Icons.error_outline, title: 'Could not load', message: '$e'),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.person_search_outlined,
              title: 'No remembered payees',
              message: 'When you pick a category with "Always use for …" ticked, '
                  'the payee shows up here.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 16),
                child: Text(
                  'New payments from these payees get their category automatically. '
                  'Removing one does not change payments already saved.',
                  style: t.bodySmall,
                ),
              ),
              Group(
                children: [
                  for (final rule in list)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                      child: Row(
                        children: [
                          IconTile(
                            icon: categories[rule.categoryId]?.icon ?? Icons.label_outline,
                            color: categories[rule.categoryId]?.color ?? p.muted,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rule.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.titleSmall?.copyWith(fontSize: 15),
                                ),
                                Text(
                                  '${rule.isDebit ? 'Paid' : 'Received'}: '
                                  '${categories[rule.categoryId]?.name ?? 'Unknown category'}',
                                  style: t.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Forget this payee',
                            icon: Icon(Icons.close, color: p.muted),
                            onPressed: () async {
                              await ref.read(txnRepoProvider).deletePayeeRule(rule.key);
                              ref.invalidate(payeeRulesProvider);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(SnackBar(content: Text('Forgot ${rule.label}')));
                            },
                          ),
                        ],
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
