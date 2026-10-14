import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
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
          preferredSize: const Size.fromHeight(116),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SearchBar(
                  hintText: 'Search payee, UPI ID or note',
                  leading: const Icon(Icons.search),
                  elevation: const WidgetStatePropertyAll(0),
                  onChanged: _onSearchChanged,
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _mode == null && _type == null,
                        showCheckmark: false,
                        onSelected: (_) => setState(() {
                          _mode = null;
                          _type = null;
                        }),
                      ),
                    ),
                    for (final (type, label, icon) in const [
                      (TxnType.credit, 'Money in', Icons.south_west),
                      (TxnType.debit, 'Money out', Icons.north_east),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(icon, size: 18),
                          label: Text(label),
                          selected: _type == type,
                          showCheckmark: false,
                          onSelected: (_) =>
                              setState(() => _type = _type == type ? null : type),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(0, 10, 8, 10),
                      child: VerticalDivider(width: 1),
                    ),
                    for (final mode in PaymentMode.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(mode.icon, size: 18),
                          label: Text(mode.shortLabel),
                          selected: _mode == mode,
                          showCheckmark: false,
                          onSelected: (_) =>
                              setState(() => _mode = _mode == mode ? null : mode),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
      body: txns.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load transactions: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _search.isNotEmpty
                      ? 'Nothing matches "$_search".'
                      : filtered
                          ? 'No transactions match these filters.'
                          : 'No transactions yet. Tap Add expense to record a cash or UPI payment.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Flatten into a totals row, day headers and transaction rows.
          final items = <Object>[if (filtered) _Totals.of(list)];
          DateTime? lastDay;
          for (final t in list) {
            final day = DateTime(t.txnTime.year, t.txnTime.month, t.txnTime.day);
            if (day != lastDay) {
              items.add(day);
              lastDay = day;
            }
            items.add(t);
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              if (item is _Totals) return _TotalsBar(totals: item);
              if (item is DateTime) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    formatDayHeader(item),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                );
              }
              final t = item as Txn;
              return TransactionTile(
                txn: t,
                category: categories[t.categoryId],
                onTap: () => openTransactionEditor(context, existing: t),
                onLongPress: () => categorizeTransaction(context, ref, t),
              );
            },
          );
        },
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          Text(
            totals.count == 1 ? '1 transaction' : '${totals.count} transactions',
            style: theme.textTheme.bodyMedium,
          ),
          if (totals.inPaise > 0)
            Text(
              'In ${formatPaise(totals.inPaise)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.income),
            ),
          if (totals.outPaise > 0)
            Text(
              'Out ${formatPaise(totals.outPaise)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.expense),
            ),
        ],
      ),
    );
  }
}
