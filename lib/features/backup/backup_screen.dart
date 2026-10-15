import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/ui.dart';
import '../../core/utils/formatters.dart';
import 'backup_codec.dart';
import 'backup_service.dart';

/// Back up to a password-protected file, restore from one, or export a
/// spreadsheet. Files are saved wherever the user picks (phone, Google Drive).
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  String? _busy;

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  static String _stamp(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _backup() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(confirm: true),
    );
    if (password == null || !mounted) return;
    setState(() => _busy = 'Locking your backup…');
    try {
      final service = ref.read(backupServiceProvider);
      final bytes = await BackupCodec.encode(await service.snapshot(), password);
      final saved = await ref.read(platformActionsProvider).saveDocument(
            name: 'dripless-backup-${_stamp(DateTime.now())}.dripless',
            mime: 'application/octet-stream',
            bytes: bytes,
          );
      if (saved) {
        await service.markBackedUp();
        ref.invalidate(lastBackupProvider);
        _toast('Backup saved. Keep the password safe: it is needed to restore.');
      }
    } on BackupException catch (e) {
      _toast(e.message);
    } on PlatformException catch (e) {
      _toast('Could not save the backup: ${e.message ?? e.code}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _restore() async {
    final Uint8List? bytes;
    try {
      bytes = await ref.read(platformActionsProvider).openDocument();
    } on PlatformException catch (e) {
      _toast('Could not open the file: ${e.message ?? e.code}');
      return;
    }
    if (bytes == null || !mounted) return;

    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(confirm: false),
    );
    if (password == null || !mounted) return;

    setState(() => _busy = 'Opening the backup…');
    final Map<String, Object?> data;
    try {
      data = await BackupCodec.decode(bytes, password);
    } on BackupException catch (e) {
      setState(() => _busy = null);
      _toast(e.message);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = null);

    final count = (data['transactions'] as List?)?.length ?? 0;
    final exported = DateTime.tryParse(data['exportedAt'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace everything with this backup?'),
        content: Text(
          'The backup${exported == null ? '' : ' from ${formatDateTime(exported)}'} has '
          '$count transaction${count == 1 ? '' : 's'}. Everything currently in Dripless '
          'is replaced by it. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replace')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = 'Restoring…');
    try {
      final restored = await ref.read(backupServiceProvider).restore(data);
      refreshAll(ref);
      _toast('Restored $restored transaction${restored == 1 ? '' : 's'}.');
    } on BackupException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Could not restore: $e. Your data was not changed.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = 'Preparing the spreadsheet…');
    try {
      final txns = await ref.read(txnRepoProvider).list();
      final categories = ref.read(categoryMapProvider);
      final csv = BackupService.toCsv(txns, categories);
      // A byte-order mark so Excel shows ₹ and names correctly.
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
      final saved = await ref.read(platformActionsProvider).saveDocument(
            name: 'dripless-transactions-${_stamp(DateTime.now())}.csv',
            mime: 'text/csv',
            bytes: bytes,
          );
      if (saved) _toast('Exported ${txns.length} transaction${txns.length == 1 ? '' : 's'}.');
    } on PlatformException catch (e) {
      _toast('Could not save the file: ${e.message ?? e.code}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final last = ref.watch(lastBackupProvider).valueOrNull;
    final busy = _busy != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 0),
            child: Text(
              last == null
                  ? 'No backup yet. Your data lives only on this phone, so save a backup '
                      'to Google Drive or another place now and then.'
                  : 'Last backup: ${formatDateTime(last)}.',
              style: t.bodyMedium?.copyWith(color: last == null ? p.attention : p.muted),
            ),
          ),
          if (busy) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kGutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(_busy!, style: t.bodySmall),
                ],
              ),
            ),
          ],
          const SectionHeader('Backup'),
          Group(
            children: [
              _ActionRow(
                icon: Icons.lock_outline,
                color: p.moneyIn,
                title: 'Save a backup file',
                subtitle: 'Locked with a password you choose. Save it to Google Drive, '
                    'your phone, or anywhere else.',
                onTap: busy ? null : _backup,
              ),
              _ActionRow(
                icon: Icons.settings_backup_restore,
                color: p.muted,
                title: 'Restore from a backup',
                subtitle: 'Replaces everything in Dripless with the backup.',
                onTap: busy ? null : _restore,
              ),
            ],
          ),
          const SectionHeader('Export'),
          Group(
            children: [
              _ActionRow(
                icon: Icons.table_chart_outlined,
                color: p.muted,
                title: 'Export as spreadsheet (CSV)',
                subtitle: 'All transactions, for Excel or Google Sheets. Not password protected.',
                onTap: busy ? null : _exportCsv,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 20, kGutter, 0),
            child: Text(
              'Moving to a new phone or reinstalling? Save a backup first, then restore it '
              'after installing.',
              style: t.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              IconTile(icon: icon, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleSmall?.copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: t.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.palette.faint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the backup password; with [confirm], asks twice.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.confirm});

  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final pw = _first.text;
    if (pw.length < BackupCodec.minPasswordLength) {
      setState(() => _error = 'Use at least ${BackupCodec.minPasswordLength} characters.');
      return;
    }
    if (widget.confirm && pw != _second.text) {
      setState(() => _error = 'The two passwords are different.');
      return;
    }
    Navigator.pop(context, pw);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(widget.confirm ? 'Choose a backup password' : 'Backup password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.confirm)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'If you forget it, the backup cannot be opened. Nobody can reset it.',
                style: t.bodySmall,
              ),
            ),
          TextField(
            controller: _first,
            autofocus: true,
            obscureText: _hidden,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: 'Password',
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Show password' : 'Hide password',
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
            onSubmitted: (_) {
              if (!widget.confirm) _submit();
            },
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _second,
              obscureText: _hidden,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'Same password again'),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.confirm ? 'Save backup' : 'Open')),
      ],
    );
  }
}

