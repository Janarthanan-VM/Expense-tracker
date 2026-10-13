import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../categories/category_picker_sheet.dart';
import 'txn.dart';

/// Opens the category picker for one transaction and saves the choice.
/// Used from the "To categorize" list and by long-pressing any transaction.
Future<void> categorizeTransaction(BuildContext context, WidgetRef ref, Txn txn) async {
  final categories = await ref.read(categoriesProvider.future);
  if (!context.mounted) return;
  final result = await showCategoryPicker(
    context,
    categories: categories,
    type: txn.type,
    selectedId: txn.categoryId,
    payeeLabel: txn.payeeLabel,
  );
  if (result == null) return;

  await ref
      .read(txnRepoProvider)
      .setCategory(txn, result.categoryId, rememberForPayee: result.remember);
  refreshAll(ref);

  if (!context.mounted) return;
  final name = ref.read(categoryMapProvider)[result.categoryId]?.name ?? 'category';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(result.remember
          ? 'Saved as $name. Future payments to ${txn.payeeLabel} will use it too.'
          : 'Saved as $name'),
    ));
}
