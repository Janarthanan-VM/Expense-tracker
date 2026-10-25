import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Deletes payments straight away and offers Undo. Works for any payment,
/// with or without a category.
Future<void> deleteTransactionsWithUndo(
  BuildContext context,
  WidgetRef ref,
  List<String> ids, {
  String? message,
}) async {
  if (ids.isEmpty) return;
  final repo = ref.read(txnRepoProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  for (final id in ids) {
    await repo.delete(id);
  }
  invalidateData(container.invalidate);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message ?? (ids.length == 1 ? 'Payment deleted' : '${ids.length} payments deleted')),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          for (final id in ids) {
            await repo.restore(id);
          }
          invalidateData(container.invalidate);
        },
      ),
    ));
}
