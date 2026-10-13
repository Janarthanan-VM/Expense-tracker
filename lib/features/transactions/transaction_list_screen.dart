import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import 'add_transaction_screen.dart';
import 'categorize_action.dart';
import 'transaction_tile.dart';
import 'txn.dart';

class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});

  @override
  ConsumerState<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  String _search = '';
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
    final txns = ref.watch(txnListProvider(_search));
    final categories = ref.watch(categoryMapProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchBar(
              hintText: 'Search payee, UPI ID or note',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: _onSearchChanged,
            ),
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
                  _search.isEmpty
                      ? 'No transactions yet. Tap Add to record your first payment.'
                      : 'Nothing matches "$_search".',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Flatten into day headers + rows.
          final items = <Object>[];
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
