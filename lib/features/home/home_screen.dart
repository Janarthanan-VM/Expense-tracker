import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../categories/category.dart';
import '../detection/detection_screen.dart';
import '../transactions/add_transaction_screen.dart';
import '../transactions/categorize_action.dart';
import '../transactions/to_categorize_screen.dart';
import '../transactions/transaction_tile.dart';
import '../transactions/payment_mode_ui.dart';
import '../transactions/txn.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(monthSummaryProvider);
    final pending = ref.watch(toCategorizeProvider);
    final recent = ref.watch(recentTxnsProvider);
    final categories = ref.watch(categoryMapProvider);
    final detection = ref.watch(detectionStatusProvider).valueOrNull;
    final showDetectionPromo = detection != null &&
        detection.supported &&
        !detection.accessEnabled &&
        !detection.promoDismissed;

    return Scaffold(
      appBar: AppBar(title: const Text('Expense Tracker')),
      body: RefreshIndicator(
        onRefresh: () async => refreshAll(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            summary.when(
              data: (s) => _MonthCard(summary: s),
              loading: () => const SizedBox(height: 132),
              error: (e, _) => Text('Could not load this month: $e'),
            ),
            if (showDetectionPromo) ...[
              const SizedBox(height: 12),
              const _DetectionPromoCard(),
            ],
            if ((pending.valueOrNull ?? const <Txn>[]).isNotEmpty) ...[
              const SizedBox(height: 12),
              _ToCategorizeCard(count: pending.valueOrNull!.length),
            ],
            if ((summary.valueOrNull?.byCategory ?? const []).isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Where it went', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _CategoryBreakdown(summary: summary.valueOrNull!, categories: categories),
            ],
            const SizedBox(height: 24),
            Text('Recent', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            recent.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Could not load transactions: $e'),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No transactions yet. Tap Add expense to record a cash or UPI payment.'),
                    )
                  : Column(
                      children: [
                        for (final t in list)
                          TransactionTile(
                            txn: t,
                            category: categories[t.categoryId],
                            showDate: true,
                            onTap: () => openTransactionEditor(context, existing: t),
                            onLongPress: () => categorizeTransaction(context, ref, t),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.summary});

  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card.filled(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Spent in ${formatMonth(summary.month)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 4),
            Text(
              formatPaise(summary.spentPaise),
              style: theme.textTheme.displaySmall?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Received ${formatPaise(summary.incomePaise)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer),
            ),
            if (summary.spentByMode.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final mode in PaymentMode.values)
                    if (summary.spentByMode[mode] != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(mode.icon, size: 18, color: scheme.onPrimaryContainer),
                          const SizedBox(width: 6),
                          Text(
                            '${mode.shortLabel} ${formatPaise(summary.spentByMode[mode]!)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetectionPromoCard extends ConsumerWidget {
  const _DetectionPromoCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Record UPI payments automatically',
                      style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Payments from Google Pay, PhonePe and your bank SMS are added for you. '
              'You just pick the category.',
              style: theme.textTheme.bodyMedium,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    await ref.read(detectionServiceProvider).setPromoDismissed(true);
                    ref.invalidate(detectionStatusProvider);
                  },
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DetectionScreen()),
                  ),
                  child: const Text('Set up'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToCategorizeCard extends StatelessWidget {
  const _ToCategorizeCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      color: scheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.label_outline, color: scheme.onTertiaryContainer),
        title: Text(
          count == 1 ? '1 payment to categorize' : '$count payments to categorize',
          style: TextStyle(color: scheme.onTertiaryContainer, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Pick a category so your totals stay accurate',
          style: TextStyle(color: scheme.onTertiaryContainer),
        ),
        trailing: Icon(Icons.chevron_right, color: scheme.onTertiaryContainer),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ToCategorizeScreen()),
        ),
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.summary, required this.categories});

  final MonthSummary summary;
  final Map<String, TxnCategory> categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = summary.byCategory.take(6).toList();

    return Column(
      children: [
        for (final item in top)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _BreakdownRow(
              category: categories[item.categoryId],
              totalPaise: item.totalPaise,
              share: summary.spentPaise == 0 ? 0 : item.totalPaise / summary.spentPaise,
              theme: theme,
            ),
          ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.category,
    required this.totalPaise,
    required this.share,
    required this.theme,
  });

  final TxnCategory? category;
  final int totalPaise;
  final double share;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final color = category?.color ?? theme.colorScheme.outline;
    return Row(
      children: [
        Icon(category?.icon ?? Icons.help_outline, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      category?.name ?? 'Not categorized',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatPaise(totalPaise),
                    style: const TextStyle(color: AppTheme.expense),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: share.clamp(0, 1).toDouble(),
                  minHeight: 6,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
