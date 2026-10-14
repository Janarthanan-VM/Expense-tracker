import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/ui.dart';
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
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final payee = widget.payeeLabel;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 4),
              child: Text('Choose category', style: t.titleLarge),
            ),
            if (payee != null)
              InkWell(
                onTap: () => setState(() => _remember = !_remember),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(kGutter - 8, 4, kGutter, 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _remember,
                        onChanged: (v) => setState(() => _remember = v ?? false),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Always use for $payee',
                              style: t.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text('Earlier uncategorized payments update too', style: t.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 96,
                  // Room for the icon plus two lines of name at large font sizes.
                  mainAxisExtent: 108,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: widget.categories.length,
                itemBuilder: (context, i) {
                  final c = widget.categories[i];
                  final selected = c.id == widget.selectedId;
                  return Material(
                    color: selected ? p.sunken : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.pop(
                        context,
                        CategoryPickResult(
                          categoryId: c.id,
                          remember: payee != null && _remember,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                        child: Column(
                          children: [
                            IconTile(icon: c.icon, color: c.color, size: 46),
                            const SizedBox(height: 8),
                            _TileLabel(
                              c.name,
                              style: t.labelMedium?.copyWith(
                                height: 1.25,
                                color: selected ? p.ink : p.muted,
                              ),
                            ),
                          ],
                        ),
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

/// Category name under its icon. A single long word ("Entertainment") is
/// scaled down to fit rather than broken mid-word.
class _TileLabel extends StatelessWidget {
  const _TileLabel(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (!text.trim().contains(' ')) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1, style: style),
      );
    }
    return Text(
      text,
      maxLines: 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
