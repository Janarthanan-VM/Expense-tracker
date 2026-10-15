import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

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
      newKind: type == TxnType.debit ? CategoryKind.expense : CategoryKind.income,
    ),
  );
}

class _CategoryPickerBody extends ConsumerStatefulWidget {
  const _CategoryPickerBody({
    required this.categories,
    required this.newKind,
    required this.selectedId,
    required this.payeeLabel,
  });

  final List<TxnCategory> categories;

  /// Kind given to a category created from this sheet.
  final CategoryKind newKind;
  final String? selectedId;
  final String? payeeLabel;

  @override
  ConsumerState<_CategoryPickerBody> createState() => _CategoryPickerBodyState();
}

class _CategoryPickerBodyState extends ConsumerState<_CategoryPickerBody> {
  /// Asks for a name, creates the category (or reuses one with that name)
  /// and picks it. Icon and colour can be set later on the Categories page.
  Future<void> _createCategory() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewNameDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final repo = ref.read(categoryRepoProvider);
    final id = await repo.idForName(name, widget.newKind) ?? await repo.addNamed(name, widget.newKind);
    ref.invalidate(categoriesProvider);
    if (!mounted) return;
    Navigator.pop(
      context,
      CategoryPickResult(categoryId: id, remember: widget.payeeLabel != null && _remember),
    );
  }

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
                itemCount: widget.categories.length + 1,
                itemBuilder: (context, i) {
                  if (i == widget.categories.length) {
                    return _NewTile(onTap: _createCategory);
                  }
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

/// Last tile in the grid: create a category by name.
class _NewTile extends StatelessWidget {
  const _NewTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.tileRadius),
                  border: Border.all(color: p.faint, width: 1.5),
                ),
                child: Icon(Icons.add, color: p.ink),
              ),
              const SizedBox(height: 8),
              Text(
                'New category',
                textAlign: TextAlign.center,
                maxLines: 2,
                style: t.labelMedium?.copyWith(height: 1.25, color: p.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Just a name; everything else can be changed later.
class _NewNameDialog extends StatefulWidget {
  const _NewNameDialog();

  @override
  State<_NewNameDialog> createState() => _NewNameDialogState();
}

class _NewNameDialogState extends State<_NewNameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 30,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'For example: Gym, Petrol, Gifts', counterText: ''),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          Text(
            'You can choose its icon and colour later on the Categories page.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _submit,
          child: const Text('Create and use'),
        ),
      ],
    );
  }
}
