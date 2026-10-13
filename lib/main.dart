import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/db/app_database.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open the encrypted on-device database before the UI starts.
  final AppDatabase database;
  try {
    database = await AppDatabase.open();
  } catch (e, stack) {
    debugPrint('Database failed to open: $e\n$stack');
    runApp(StartupErrorApp(error: e));
    return;
  }

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const ExpenseTrackerApp(),
    ),
  );
}

/// Shown instead of a blank screen when the database cannot be opened.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'The app could not open its data',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Close the app and open it again. If this keeps happening, '
                  'send the details below to the developer.',
                ),
                const SizedBox(height: 16),
                Expanded(child: SingleChildScrollView(child: SelectableText('$error'))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
