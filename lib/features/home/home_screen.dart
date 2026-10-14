import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/ui.dart';
import '../../core/utils/formatters.dart';
import '../categories/category.dart';
import '../detection/detection_screen.dart';
import '../transactions/add_transaction_screen.dart';
import '../transactions/categorize_action.dart';
import '../transactions/payment_mode_ui.dart';
import '../transactions/to_categorize_screen.dart';
import '../transactions/transaction_tile.dart';
import '../transactions/txn.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.onSeeAll});

  /// Opens the Transactions tab.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(monthSummaryProvider);
    final daily = ref.watch(dailySpendProvider).valueOrNull;
    final pending = ref.watch(toCategorizeProvider).valueOrNull ?? const <Txn>[];
    final recent = ref.watch(recentTxnsProvider);
    final categories = ref.watch(categoryMapProvider);
    final detection = ref.watch(detectionStatusProvider).valueOrNull;
    final showDetectionPromo = detection != null &&
        detection.supported &&
        !detection.accessEnabled &&
        !detection.smsPermission &&
        !detection.promoDismissed;
    final s = summary.valueOrNull;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: context.palette.ink,
          onRefresh: () async => refreshAll(ref),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              if (summary.hasError)
                Padding(
                  padding: const EdgeInsets.all(kGutter),
                  child: Text('Could not load this month: ${summary.error}'),
                ),
              _Hero(summary: s),
              if (daily != null && daily.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(kGutter, 28, kGutter, 0),
                  child: DailyBars(totals: daily, today: DateTime.now().day),
                ),
              if (pending.isNotEmpty) ...[
                const SizedBox(height: 24),
                _AttentionRow(count: pending.length),
              ],
              if (showDetectionPromo) ...[
                const SizedBox(height: 12),
                const _DetectionPromo(),
              ],
              if (s != null && s.byCategory.isNotEmpty) ...[
                const SectionHeader('Where it went'),
                _Breakdown(summary: s, categories: categories),
              ],
              SectionHeader(
                'Recent',
                action: onSeeAll == null
                    ? null
                    : TextButton(onPressed: onSeeAll, child: const Text('See all')),
              ),
              recent.when(
                loading: () => const SizedBox(height: 120),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kGutter),
                  child: Text('Could not load transactions: $e'),
                ),
                data: (list) => list.isEmpty
                    ? const _FirstRun()
                    : Group(
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
      ),
    );
  }
}

/// Month name, the amount spent, and money in / kept.
class _Hero extends StatelessWidget {
  const _Hero({required this.summary});

  final MonthSummary? summary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final s = summary;
    final month = s?.month ?? DateTime.now();
    final spent = s?.spentPaise ?? 0;
    final income = s?.incomePaise ?? 0;
    final kept = income - spent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 20, kGutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatMonth(month), style: t.titleSmall?.copyWith(color: p.muted)),
          const SizedBox(height: 18),
          Text('Spent', style: t.bodyMedium?.copyWith(color: p.muted)),
          const SizedBox(height: 4),
          Semantics(
            label: 'Spent ${formatPaise(spent)} this month',
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                s == null ? ' ' : formatPaise(spent),
                style: t.displayLarge?.copyWith(fontFeatures: kTabular),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _Stat(
                label: 'Received',
                value: formatPaise(income),
                color: p.moneyIn,
              ),
              _Stat(
                label: kept >= 0 ? 'Saved' : 'Overspent',
                value: formatPaise(kept.abs()),
                color: kept >= 0 ? p.ink : p.attention,
              ),
            ],
          ),
          if (s != null && s.spentByMode.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final mode in PaymentMode.values)
                  if (s.spentByMode[mode] != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(mode.icon, size: 16, color: p.muted),
                        const SizedBox(width: 6),
                        Text(
                          '${mode.shortLabel} ${formatPaise(s.spentByMode[mode]!)}',
                          style: t.bodySmall?.copyWith(fontFeatures: kTabular),
                        ),
                      ],
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '$label  ', style: t.bodyMedium?.copyWith(color: context.palette.muted)),
        TextSpan(
          text: value,
          style: t.titleMedium?.copyWith(color: color, fontFeatures: kTabular),
        ),
      ]),
    );
  }
}

/// One thin bar per day of the month. Today is marigold; days still to come
/// are a faint baseline so the month's shape is visible.
class DailyBars extends StatelessWidget {
  const DailyBars({super.key, required this.totals, required this.today, this.height = 72});

  final List<int> totals;

  /// Day of month (1-based) to highlight.
  final int today;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final maxValue = totals.fold<int>(0, math.max);
    final todayIndex = (today - 1).clamp(0, totals.length - 1);
    final todayAmount = totals[todayIndex];

    return Semantics(
      label: 'Daily spending this month. Today ${formatPaise(todayAmount)}.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Each day', style: t.bodySmall)),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                'Today ${formatPaise(todayAmount)}',
                style: t.labelMedium?.copyWith(fontFeatures: kTabular),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < totals.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: _Bar(
                        fraction: maxValue == 0 ? 0 : totals[i] / maxValue,
                        color: i == todayIndex
                            ? p.accent
                            : i > todayIndex
                                ? p.line
                                : p.bar,
                        height: height,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('1', style: t.labelSmall?.copyWith(color: p.faint)),
              const Spacer(),
              Text('${totals.length}', style: t.labelSmall?.copyWith(color: p.faint)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color, required this.height});

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Zero days still show a short stub so the row reads as a calendar.
    final h = math.max(3.0, height * fraction.clamp(0.0, 1.0));
    return Container(
      height: h,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
    );
  }
}

/// "5 payments need a category" — the one thing on Home that asks for action.
class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Group(
      children: [
        ListTile(
          minVerticalPadding: 14,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: p.accent,
              borderRadius: BorderRadius.circular(AppTheme.tileRadius),
            ),
            alignment: Alignment.center,
            child: Text(
              count > 99 ? '99+' : '$count',
              style: t.labelLarge?.copyWith(color: p.onAccent, fontWeight: FontWeight.w800),
            ),
          ),
          title: Text(count == 1 ? 'Payment needs a category' : 'Payments need a category'),
          subtitle: const Text('Pick one so your totals stay accurate'),
          trailing: Icon(Icons.chevron_right, color: p.muted),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ToCategorizeScreen()),
          ),
        ),
      ],
    );
  }
}

/// Spending split by category: one stacked bar, then the top categories.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.summary, required this.categories});

  final MonthSummary summary;
  final Map<String, TxnCategory> categories;

  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final total = summary.spentPaise;
    final items = summary.byCategory.where((c) => c.totalPaise > 0).toList();
    final top = items.take(_shown).toList();
    final rest = items.skip(_shown).fold<int>(0, (sum, c) => sum + c.totalPaise);

    Color colorOf(String? id) => categories[id]?.color ?? p.faint;
    String nameOf(String? id) =>
        id == null ? 'Not categorized' : (categories[id]?.name ?? 'Other');

    final segments = <(Color, int)>[
      for (final c in top) (colorOf(c.categoryId), c.totalPaise),
      if (rest > 0) (p.bar, rest),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kGutter),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < segments.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: math.max(1, (segments[i].$2 * 1000 / math.max(1, total)).round()),
                      child: ColoredBox(color: segments[i].$1),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final c in top)
            _BreakdownRow(
              color: colorOf(c.categoryId),
              name: nameOf(c.categoryId),
              amount: c.totalPaise,
              share: total == 0 ? 0 : c.totalPaise / total,
            ),
          if (rest > 0)
            _BreakdownRow(
              color: p.bar,
              name: 'Everything else',
              amount: rest,
              share: total == 0 ? 0 : rest / total,
            ),
          if (items.isEmpty) Text('No spending yet', style: t.bodySmall),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.color,
    required this.name,
    required this.amount,
    required this.share,
  });

  final Color color;
  final String name;
  final int amount;
  final double share;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final pct = (share * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 44,
            child: Text(
              pct < 1 ? '<1%' : '$pct%',
              textAlign: TextAlign.right,
              style: t.bodySmall?.copyWith(fontFeatures: kTabular),
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 84),
            child: Text(
              formatPaise(amount),
              textAlign: TextAlign.right,
              style: t.titleSmall?.copyWith(color: p.ink, fontFeatures: kTabular),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectionPromo extends ConsumerWidget {
  const _DetectionPromo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Group(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconTile(icon: Icons.sms_outlined, color: p.moneyIn),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Record payments automatically', style: t.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Credits and debits from your bank SMS, Google Pay and PhonePe '
                          'are added for you. You only pick the category.',
                          style: t.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () async {
                      await ref.read(detectionServiceProvider).setPromoDismissed(true);
                      ref.invalidate(detectionStatusProvider);
                    },
                    child: Text('Not now', style: TextStyle(color: p.muted)),
                  ),
                  const SizedBox(width: 4),
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
      ],
    );
  }
}

class _FirstRun extends StatelessWidget {
  const _FirstRun();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 0),
      child: Text(
        'Nothing yet. Tap + to add a cash or UPI payment, or set up automatic '
        'recording in Settings.',
        style: t.bodyMedium?.copyWith(color: context.palette.muted),
      ),
    );
  }
}
