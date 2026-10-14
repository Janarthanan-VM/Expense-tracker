import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/ui.dart';
import '../../core/utils/formatters.dart';
import 'add_transaction_screen.dart';
import 'categorize_action.dart';
import 'payment_mode_ui.dart';
import 'transaction_tile.dart';
import 'txn.dart';

class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});

  @override
  ConsumerState<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  String _search = '';
  PaymentMode? _mode;
  TxnType? _type;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _search = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(txnListProvider((search: _search, mode: _mode, type: _type)));
    final filtered = _search.isNotEmpty || _mode != null || _type != null;
    final categories = ref.watch(categoryMapProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(118),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter - 4, 4, kGutter - 4, 10),
                child: SearchBar(
                  hintText: 'Search name, UPI ID or note',
                  leading: Icon(Icons.search, color: context.palette.muted),
                  onChanged: _onSearchChanged,
                ),
              ),
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(kGutter - 4, 2, kGutter - 4, 8),
                  children: [
                    Pill(
                      label: 'All',
                      selected: _mode == null && _type == null,
                      onTap: () => setState(() {
                        _mode = null;
                        _type = null;
                      }),
                    ),
                    const SizedBox(width: 8),
                    for (final (type, label, icon) in const [
                      (TxnType.credit, 'Money in', Icons.south_west),
                      (TxnType.debit, 'Money out', Icons.north_east),
                    ]) ...[
                      Pill(
                        label: label,
                        icon: icon,
                        selected: _type == type,
                        onTap: () => setState(() => _type = _type == type ? null : type),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
                      child: VerticalDivider(width: 1, color: context.palette.line),
                    ),
                    for (final mode in PaymentMode.values) ...[
                      Pill(
                        label: mode.shortLabel,
                        icon: mode.icon,
                        selected: _mode == mode,
                        onTap: () => setState(() => _mode = _mode == mode ? null : mode),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: txns.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Could not load transactions',
          message: '$e',
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: _search.isNotEmpty ? Icons.search_off : Icons.receipt_long_outlined,
              title: _search.isNotEmpty
                  ? 'Nothing matches "$_search"'
                  : filtered
                      ? 'No transactions match these filters'
                      : 'No transactions yet',
              message: filtered ? null : 'Tap + to add a cash or UPI payment.',
            );
          }

          final days = _groupByDay(list);
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: days.length + (filtered ? 1 : 0),
            itemBuilder: (context, i) {
              if (filtered && i == 0) return _TotalsBar(totals: _Totals.of(list));
              final day = days[i - (filtered ? 1 : 0)];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DayHeader(day: day.date, outPaise: day.outPaise, inPaise: day.inPaise),
                  Group(
                    children: [
                      for (final t in day.txns)
                        TransactionTile(
                          txn: t,
                          category: categories[t.categoryId],
                          onTap: () => openTransactionEditor(context, existing: t),
                          onLongPress: () => categorizeTransaction(context, ref, t),
                        ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static List<_Day> _groupByDay(List<Txn> list) {
    final days = <_Day>[];
    for (final t in list) {
      final date = DateTime(t.txnTime.year, t.txnTime.month, t.txnTime.day);
      if (days.isEmpty || days.last.date != date) days.add(_Day(date));
      days.last.add(t);
    }
    return days;
  }
}

class _Day {
  _Day(this.date);

  final DateTime date;
  final List<Txn> txns = [];
  int outPaise = 0;
  int inPaise = 0;

  void add(Txn t) {
    txns.add(t);
    if (t.status == TxnStatus.failed) return;
    if (t.type == TxnType.debit) {
      outPaise += t.amountPaise;
    } else {
      inPaise += t.amountPaise;
    }
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.outPaise, required this.inPaise});

  final DateTime day;
  final int outPaise;
  final int inPaise;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 24, kGutter, 10),
      child: Row(
        children: [
          Expanded(child: Text(formatDayHeader(day), style: t.titleSmall)),
          if (inPaise > 0)
            Text(
              '+${formatPaise(inPaise)}',
              style: t.bodySmall?.copyWith(color: p.moneyIn, fontFeatures: kTabular),
            ),
          if (inPaise > 0 && outPaise > 0) const SizedBox(width: 12),
          if (outPaise > 0)
            Text(
              '−${formatPaise(outPaise)}',
              style: t.bodySmall?.copyWith(fontFeatures: kTabular),
            ),
        ],
      ),
    );
  }
}

/// Money in and out across the transactions currently shown.
class _Totals {
  const _Totals({required this.inPaise, required this.outPaise, required this.count});

  factory _Totals.of(List<Txn> list) {
    var inPaise = 0;
    var outPaise = 0;
    for (final t in list) {
      if (t.status == TxnStatus.failed) continue;
      if (t.type == TxnType.credit) {
        inPaise += t.amountPaise;
      } else {
        outPaise += t.amountPaise;
      }
    }
    return _Totals(inPaise: inPaise, outPaise: outPaise, count: list.length);
  }

  final int inPaise;
  final int outPaise;
  final int count;
}

class _TotalsBar extends StatelessWidget {
  const _TotalsBar({required this.totals});

  final _Totals totals;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    Widget figure(String label, String value, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t.bodySmall),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: t.titleLarge?.copyWith(color: color, fontFeatures: kTabular),
                ),
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
      child: Row(
        children: [
          figure('Money in', formatPaise(totals.inPaise), p.moneyIn),
          figure('Money out', formatPaise(totals.outPaise), p.moneyOut),
          figure(
            'Transactions',
            '${totals.count}',
            p.ink,
          ),
        ],
      ),
    );
  }
}
