import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../categories/category.dart';
import '../categories/category_picker_sheet.dart';
import 'payment_mode_ui.dart';
import 'txn.dart';

Future<void> openTransactionEditor(
  BuildContext context, {
  Txn? existing,
  PaymentMode? mode,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AddTransactionScreen(existing: existing, initialMode: mode),
    ),
  );
}

/// Add a new transaction manually, or edit any existing one.
class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key, this.existing, this.initialMode});

  final Txn? existing;

  /// Payment method for a new entry. Manual entries default to cash.
  final PaymentMode? initialMode;

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _payee;
  late final TextEditingController _note;

  late TxnType _type;
  late PaymentMode _mode;
  String? _categoryId;
  bool _remember = false;
  late DateTime _time;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(text: e == null ? '' : paiseToInput(e.amountPaise));
    _payee = TextEditingController(text: e?.payeeName ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _type = e?.type ?? TxnType.debit;
    _mode = e?.paymentMode ?? widget.initialMode ?? PaymentMode.cash;
    _categoryId = e?.categoryId;
    _time = e?.txnTime ?? DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final categories = ref.read(categoriesProvider).valueOrNull ?? const <TxnCategory>[];
    final payee = _payee.text.trim();
    final result = await showCategoryPicker(
      context,
      categories: categories,
      type: _type,
      selectedId: _categoryId,
      payeeLabel: payee.isEmpty ? widget.existing?.payeeVpa : payee,
    );
    if (result == null) return;
    setState(() {
      _categoryId = result.categoryId;
      _remember = result.remember;
    });
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (!mounted) return;
    final t = time ?? TimeOfDay.fromDateTime(_time);
    setState(() => _time = DateTime(date.year, date.month, date.day, t.hour, t.minute));
  }

  void _changeType(TxnType type) {
    final category = ref.read(categoryMapProvider)[_categoryId];
    final stillValid = category == null ||
        category.kind == CategoryKind.transfer ||
        (type == TxnType.debit) == (category.kind == CategoryKind.expense);
    setState(() {
      _type = type;
      if (!stillValid) _categoryId = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final repo = ref.read(txnRepoProvider);
    final base = widget.existing;
    final now = DateTime.now();
    final payee = _payee.text.trim();
    final note = _note.text.trim();

    final txn = Txn(
      id: base?.id ?? const Uuid().v4(),
      amountPaise: parseRupeesToPaise(_amount.text)!,
      type: _type,
      status: base?.status ?? TxnStatus.success,
      source: base?.source ?? TxnSource.manual,
      paymentMode: _mode,
      categoryId: _categoryId,
      categorySource: _categoryId == null
          ? null
          : (_categoryId == base?.categoryId && base?.isReviewed == true
              ? base?.categorySource
              : CategorySource.user),
      // Saving from this screen counts as the user confirming the category.
      isReviewed: _categoryId != null,
      payeeName: payee.isEmpty ? null : payee,
      payeeVpa: base?.payeeVpa,
      upiRef: base?.upiRef,
      upiApp: base?.upiApp,
      note: note.isEmpty ? null : note,
      txnTime: _time,
      createdAt: base?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      if (base == null) {
        final saved = await repo.add(txn);
        if (saved == null) {
          throw StateError('A payment with this UPI reference is already saved.');
        }
      } else {
        await repo.update(txn);
      }
      if (_remember && _categoryId != null) {
        await repo.setCategory(txn, _categoryId!, rememberForPayee: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
      return;
    }

    refreshAll(ref);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: const Text('It will be removed from all lists and totals.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(txnRepoProvider).delete(widget.existing!.id);
    refreshAll(ref);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = ref.watch(categoryMapProvider)[_categoryId];
    final e = widget.existing;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit transaction' : 'Add transaction'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<TxnType>(
              segments: const [
                ButtonSegment(value: TxnType.debit, label: Text('Paid'), icon: Icon(Icons.north_east)),
                ButtonSegment(value: TxnType.credit, label: Text('Received'), icon: Icon(Icons.south_west)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => _changeType(s.first),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _amount,
              autofocus: !_isEdit,
              style: theme.textTheme.headlineMedium,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
              validator: (v) =>
                  parseRupeesToPaise(v ?? '') == null ? 'Enter an amount above ₹0' : null,
            ),
            const SizedBox(height: 16),
            Text(
              _type == TxnType.debit ? 'Paid with' : 'Received as',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            PaymentModeSelector(
              selected: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _payee,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: _type == TxnType.debit ? 'Paid to' : 'Received from',
                hintText: _mode == PaymentMode.cash
                    ? 'For example: tea shop, auto, vegetables (optional)'
                    : 'Shop or person name (optional)',
              ),
            ),
            const SizedBox(height: 16),
            _FieldTile(
              label: 'Category',
              leading: CircleAvatar(
                backgroundColor: (category?.color ?? theme.colorScheme.outline).withValues(alpha: 0.14),
                foregroundColor: category?.color ?? theme.colorScheme.outline,
                child: Icon(category?.icon ?? Icons.category_outlined),
              ),
              value: category?.name ?? 'Choose category',
              onTap: _pickCategory,
            ),
            if (_remember && category != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  'Future payments to this payee will use ${category.name}.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            _FieldTile(
              label: 'Date and time',
              leading: const Icon(Icons.event),
              value: formatDateTime(_time),
              onTap: _pickDateTime,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (e != null && (e.upiRef != null || e.source != TxnSource.manual)) ...[
              const SizedBox(height: 16),
              _UpiDetails(txn: e),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(_isEdit ? 'Save changes' : 'Save transaction'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.label,
    required this.leading,
    required this.value,
    required this.onTap,
  });

  final String label;
  final Widget leading;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      leading: leading,
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(value, style: Theme.of(context).textTheme.bodyLarge),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _UpiDetails extends StatelessWidget {
  const _UpiDetails({required this.txn});

  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (txn.payeeVpa != null) ('UPI ID', txn.payeeVpa!),
      if (txn.upiRef != null) ('UPI reference', txn.upiRef!),
      if (txn.upiApp != null) ('Paid using', txn.upiApp!),
      ('Captured from', switch (txn.source) {
        TxnSource.manual => 'Added manually',
        TxnSource.scanPay => 'Scan & Pay',
        TxnSource.notification => 'Payment notification',
        TxnSource.sms => 'Bank SMS',
        TxnSource.ocr => 'Screenshot',
        TxnSource.statement => 'Bank statement',
      }),
    ];
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
                    Flexible(child: SelectableText(value, textAlign: TextAlign.end)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
