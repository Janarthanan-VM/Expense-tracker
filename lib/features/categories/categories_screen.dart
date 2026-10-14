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
            padding: const EdgeInsets.only(right: 12),
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
                'Tap a category to rename it. Switch one off to hide it from the picker; '
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

  Future<void> _rename(BuildContext context, WidgetRef ref, TxnCategory c) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initialName: c.name),
    );
    if (name == null || name.isEmpty || name == c.name) return;
    await ref.read(categoryRepoProvider).rename(c.id, name);
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

/// Owns its text controller, so it is disposed only after the dialog has
/// finished closing.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename category'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Rename'),
        ),
      ],
    );
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
  const _NewCategoryDialog();

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  final _name = TextEditingController();
  CategoryKind _kind = CategoryKind.expense;
  String _iconKey = kCategoryIcons.keys.first;
  int _color = kCategoryColors.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('New category'),
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
              const SizedBox(height: 16),
              SegmentedButton<CategoryKind>(
                segments: [
                  for (final k in CategoryKind.values)
                    ButtonSegment(value: k, label: Text(k.label)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
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
          child: const Text('Create'),
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
            Switch(value: !c.isHidden, onChanged: onVisible),
          ],
        ),
      ),
    );
  }
}
