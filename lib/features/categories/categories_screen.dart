import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/ui.dart';
import 'category.dart';
import 'category_icons.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: kGutter - 4),
            child: OutlinedButton.icon(
              onPressed: () => _addCategory(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New'),
            ),
          ),
        ],
      ),
      body: categories.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Could not load categories',
          message: '$e',
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 0),
              child: Text(
                'Tap a category to change its name, icon or colour. Use the eye to hide one from the picker; '
                'payments already in it keep it.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final kind in CategoryKind.values) ...[
              SectionHeader(kind.label),
              Group(
                children: [
                  for (final c in list.where((c) => c.kind == kind))
                    _CategoryRow(
                      category: c,
                      onTap: () => _rename(context, ref, c),
                      onVisible: (show) async {
                        await ref.read(categoryRepoProvider).setHidden(c.id, !show);
                        refreshAll(ref);
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Edit name, icon and colour (the kind stays, so totals keep their meaning).
  Future<void> _rename(BuildContext context, WidgetRef ref, TxnCategory c) async {
    final draft = await showDialog<_CategoryDraft>(
      context: context,
      builder: (_) => _NewCategoryDialog(initial: c),
    );
    if (draft == null || draft.name.isEmpty) return;
    await ref.read(categoryRepoProvider).update(
          c.id,
          name: draft.name,
          iconKey: draft.iconKey,
          colorValue: draft.colorValue,
        );
    refreshAll(ref);
  }

  Future<void> _addCategory(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_CategoryDraft>(
      context: context,
      builder: (_) => const _NewCategoryDialog(),
    );
    if (draft == null) return;
    await ref.read(categoryRepoProvider).add(
          name: draft.name,
          kind: draft.kind,
          iconKey: draft.iconKey,
          colorValue: draft.colorValue,
        );
    refreshAll(ref);
  }
}

class _CategoryDraft {
  const _CategoryDraft(this.name, this.kind, this.iconKey, this.colorValue);

  final String name;
  final CategoryKind kind;
  final String iconKey;
  final int colorValue;
}

class _NewCategoryDialog extends StatefulWidget {
  const _NewCategoryDialog({this.initial});

  /// Set when editing an existing category.
  final TxnCategory? initial;

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initial?.name ?? '');
  late CategoryKind _kind = widget.initial?.kind ?? CategoryKind.expense;
  late String _iconKey = widget.initial?.iconKey ?? kCategoryIcons.keys.first;
  late int _color = widget.initial?.colorValue ?? kCategoryColors.first;

  bool get _editing => widget.initial != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_editing ? 'Edit category' : 'New category'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (_) => setState(() {}),
              ),
              if (!_editing) ...[
                const SizedBox(height: 16),
                SegmentedButton<CategoryKind>(
                  segments: [
                    for (final k in CategoryKind.values)
                      ButtonSegment(value: k, label: Text(k.label)),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
              ],
              const SizedBox(height: 16),
              Text('Icon', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final entry in kCategoryIcons.entries)
                    IconButton(
                      isSelected: entry.key == _iconKey,
                      style: IconButton.styleFrom(
                        backgroundColor: entry.key == _iconKey
                            ? Color(_color).withValues(alpha: 0.18)
                            : null,
                      ),
                      color: entry.key == _iconKey ? Color(_color) : null,
                      icon: Icon(entry.value),
                      onPressed: () => setState(() => _iconKey = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Colour', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in kCategoryColors)
                    GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: Color(c),
                        child: c == _color
                            ? const Icon(Icons.check, size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _CategoryDraft(_name.text.trim(), _kind, _iconKey, _color),
                  ),
          child: Text(_editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.onTap, required this.onVisible});

  final TxnCategory category;
  final VoidCallback onTap;
  final ValueChanged<bool> onVisible;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final c = category;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Opacity(
              opacity: c.isHidden ? 0.4 : 1,
              child: IconTile(icon: c.icon, color: c.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: t.titleSmall?.copyWith(
                      fontSize: 15,
                      color: c.isHidden ? p.faint : p.ink,
                    ),
                  ),
                  if (c.isHidden) Text('Hidden from the picker', style: t.bodySmall),
                ],
              ),
            ),
            IconButton(
              tooltip: c.isHidden ? 'Show in picker' : 'Hide from picker',
              onPressed: () => onVisible(c.isHidden),
              icon: Icon(
                c.isHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: c.isHidden ? p.faint : p.muted,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
