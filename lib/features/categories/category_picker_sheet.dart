import 'package:flutter/material.dart';

import '../transactions/txn.dart';
import 'category.dart';

class CategoryPickResult {
  const CategoryPickResult({required this.categoryId, required this.remember});

  final String categoryId;

  /// User asked to always use this category for the same payee.
  final bool remember;
}

/// Bottom sheet to pick a category. Expenses see expense + transfer
/// categories; income sees income + transfer categories.
Future<CategoryPickResult?> showCategoryPicker(
  BuildContext context, {
  required List<TxnCategory> categories,
  required TxnType type,
  String? selectedId,
  String? payeeLabel,
}) {
  final allowed = type == TxnType.debit
      ? {CategoryKind.expense, CategoryKind.transfer}
      : {CategoryKind.income, CategoryKind.transfer};
  final visible = categories
      .where((c) => allowed.contains(c.kind) && (!c.isHidden || c.id == selectedId))
      .toList();

  return showModalBottomSheet<CategoryPickResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CategoryPickerBody(
      categories: visible,
      selectedId: selectedId,
      payeeLabel: payeeLabel,
    ),
  );
}

class _CategoryPickerBody extends StatefulWidget {
  const _CategoryPickerBody({
    required this.categories,
    required this.selectedId,
    required this.payeeLabel,
  });

  final List<TxnCategory> categories;
  final String? selectedId;
  final String? payeeLabel;

  @override
  State<_CategoryPickerBody> createState() => _CategoryPickerBodyState();
}

class _CategoryPickerBodyState extends State<_CategoryPickerBody> {
  bool _remember = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payee = widget.payeeLabel;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Choose category', style: theme.textTheme.titleLarge),
            ),
            if (payee != null)
              CheckboxListTile(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? false),
                title: Text('Always use this for $payee'),
                subtitle: const Text('Also updates earlier uncategorized payments'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 104,
                  mainAxisExtent: 96,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: widget.categories.length,
                itemBuilder: (context, i) {
                  final c = widget.categories[i];
                  final selected = c.id == widget.selectedId;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(
                      context,
                      CategoryPickResult(
                        categoryId: c.id,
                        remember: payee != null && _remember,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: selected
                            ? Border.all(color: theme.colorScheme.primary, width: 2)
                            : null,
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            backgroundColor: c.color.withValues(alpha: 0.14),
                            foregroundColor: c.color,
                            child: Icon(c.icon),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            c.name,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
