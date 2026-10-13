import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../categories/categories_screen.dart';
import '../settings/settings_screen.dart';
import '../transactions/add_transaction_screen.dart';
import '../transactions/categorize_action.dart';
import '../transactions/to_categorize_screen.dart';
import '../transactions/transaction_list_screen.dart';
import 'home_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  int _index = 0;

  static const _pages = <Widget>[
    HomeScreen(),
    TransactionListScreen(),
    CategoriesScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(detectionServiceProvider).onEventsAvailable = _syncDetected;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncDetected());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ref.read(detectionServiceProvider).onEventsAvailable = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(detectionStatusProvider);
      _syncDetected();
    }
  }

  /// Saves payments detected while the app was closed, then opens the one
  /// whose notification the user tapped (if any).
  Future<void> _syncDetected() async {
    try {
      final changed = await ref.read(detectionSyncProvider).run();
      if (!mounted) return;
      if (changed) refreshAll(ref);

      final openId = await ref.read(detectionServiceProvider).consumeOpenRequest();
      if (openId == null || !mounted) return;
      final txn = await ref.read(txnRepoProvider).byId(openId);
      if (!mounted) return;
      if (txn != null) {
        await categorizeTransaction(context, ref, txn);
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ToCategorizeScreen()),
        );
      }
    } catch (e) {
      debugPrint('Could not sync detected payments: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: _index <= 1
          ? FloatingActionButton.extended(
              onPressed: () => openTransactionEditor(context),
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Transactions'),
          NavigationDestination(icon: Icon(Icons.category_outlined), selectedIcon: Icon(Icons.category), label: 'Categories'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
