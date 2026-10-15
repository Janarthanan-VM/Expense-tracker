import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/ui.dart';
import '../../core/utils/formatters.dart';
import '../categories/category.dart';
import '../categories/category_picker_sheet.dart';
import 'split_sheet.dart';
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

  /// Your part of a shared bill; null when the bill is not split.
  int? _myShare;
  bool _saving = false;

  /// Shown under the amount; the field itself is too narrow for an error line.
  String? _amountError;

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
    _myShare = e?.isSplit == true ? e!.mySharePaise : null;
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
    if (parseRupeesToPaise(_amount.text) == null) {
      setState(() => _amountError = 'Enter an amount above ₹0');
      return;
    }
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
      // A split only applies to money paid, and only while your share is
      // smaller than the bill.
      mySharePaise: _type == TxnType.debit &&
              _myShare != null &&
              _myShare! < parseRupeesToPaise(_amount.text)!
          ? _myShare
          : null,
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

  /// Deletes straight away and offers Undo on the screen underneath.
  Future<void> _delete() async {
    final id = widget.existing!.id;
    final repo = ref.read(txnRepoProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    await repo.delete(id);
    refreshAll(ref);
    if (mounted) Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Transaction deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await repo.restore(id);
            invalidateData(container.invalidate);
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final category = ref.watch(categoryMapProvider)[_categoryId];
    final e = widget.existing;
    final paid = _type == TxnType.debit;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(_isEdit ? 'Edit transaction' : (paid ? 'New expense' : 'Money received')),
        titleSpacing: 0,
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const SizedBox(height: 8),
            Center(
              child: _DirectionSwitch(
                paid: paid,
                onChanged: (v) => _changeType(v ? TxnType.debit : TxnType.credit),
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kGutter),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, right: 6),
                    child: Text('₹', style: t.headlineMedium?.copyWith(color: p.muted)),
                  ),
                  Flexible(
                    child: IntrinsicWidth(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 48),
                        child: _amountField(p, t, paid),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_amountError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _amountError!,
                  textAlign: TextAlign.center,
                  style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kGutter),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in PaymentMode.values)
                    Pill(
                      label: mode.shortLabel,
                      selected: _mode == mode,
                      onTap: () => setState(() => _mode = mode),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Group(
              children: [
                _Row(
                  icon: paid ? Icons.storefront_outlined : Icons.person_outline,
                  child: TextField(
                    controller: _payee,
                    textCapitalization: TextCapitalization.words,
                    style: t.bodyLarge,
                    decoration: _inline(
                      paid
                          ? (_mode == PaymentMode.cash ? 'Paid to (tea shop, auto…)' : 'Paid to')
                          : 'Received from',
                      p,
                      t,
                    ),
                  ),
                ),
                _Row(
                  icon: category?.icon ?? Icons.label_outline,
                  iconColor: category?.color,
                  onTap: _pickCategory,
                  child: Text(
                    category?.name ?? 'Choose category',
                    style: t.bodyLarge?.copyWith(
                      color: category == null ? p.attention : p.ink,
                      fontWeight: category == null ? FontWeight.w700 : null,
                    ),
                  ),
                ),
                if (paid)
                  _Row(
                    icon: Icons.call_split,
                    onTap: _editSplit,
                    // Rebuilds as the amount is typed.
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _amount,
                      builder: (context, value, child) => _splitLabel(t, p),
                    ),
                  ),
                _Row(
                  icon: Icons.event_outlined,
                  onTap: _pickDateTime,
                  child: Text(formatDateTime(_time), style: t.bodyLarge),
                ),
                _Row(
                  icon: Icons.notes_outlined,
                  child: TextField(
                    controller: _note,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: t.bodyLarge,
                    decoration: _inline('Note', p, t),
                  ),
                ),
              ],
            ),
            if (_remember && category != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter + 4, 10, kGutter, 0),
                child: Text(
                  'Future payments to this payee will use ${category.name}.',
                  style: t.bodySmall,
                ),
              ),
            if (e != null && (e.upiRef != null || e.source != TxnSource.manual)) ...[
              const SectionHeader('Details'),
              _UpiDetails(txn: e),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _saveBar(context),
    );
  }

  Widget _amountField(AppPalette p, TextTheme t, bool paid) => TextFormField(
                controller: _amount,
                autofocus: !_isEdit,
                textAlign: TextAlign.center,
                style: t.displayMedium?.copyWith(
                  color: paid ? p.moneyOut : p.moneyIn,
                  fontFeatures: kTabular,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  hintText: '0',
                  hintStyle: t.displayMedium?.copyWith(color: p.faint),
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) {
                  if (_amountError != null) setState(() => _amountError = null);
                },
              );

  Widget _splitLabel(TextTheme t, AppPalette p) {
    final total = parseRupeesToPaise(_amount.text);
    final share = _myShare;
    if (share == null || total == null || share >= total) {
      return Text('Split with friends', style: t.bodyLarge?.copyWith(color: p.faint));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your share ${formatPaise(share)}', style: t.bodyLarge),
        Text('Friends owe you ${formatPaise(total - share)}', style: t.bodySmall),
      ],
    );
  }

  Future<void> _editSplit() async {
    final total = parseRupeesToPaise(_amount.text);
    if (total == null) {
      setState(() => _amountError = 'Enter the amount first, then split it');
      return;
    }
    final result = await showSplitSheet(context, totalPaise: total, currentShare: _myShare);
    if (result == null) return;
    setState(() => _myShare = result.mySharePaise);
  }

  Widget _saveBar(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            kGutter,
            8,
            kGutter,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            child: Text(_isEdit ? 'Save changes' : 'Save'),
          ),
        ),
      );

  static InputDecoration _inline(String hint, AppPalette p, TextTheme t) => InputDecoration(
        hintText: hint,
        hintStyle: t.bodyLarge?.copyWith(color: p.faint),
        filled: false,
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
      );
}

/// Paid / Received switch shown at the top of the screen.
class _DirectionSwitch extends StatelessWidget {
  const _DirectionSwitch({required this.paid, required this.onChanged});

  final bool paid;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget option(String label, bool value) {
      final selected = paid == value;
      return Semantics(
        selected: selected,
        button: true,
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? p.raised : Colors.transparent,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? p.ink : p.muted,
                  ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.sunken, borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [option('Paid', true), option('Received', false)],
      ),
    );
  }
}

/// One row inside the form group: icon on the left, content on the right.
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.child, this.onTap, this.iconColor});

  final IconData icon;
  final Widget child;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconTile(icon: icon, color: iconColor ?? p.muted, size: 36),
          const SizedBox(width: 14),
          Expanded(child: child),
          if (onTap != null) Icon(Icons.chevron_right, color: p.faint),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

class _UpiDetails extends StatelessWidget {
  const _UpiDetails({required this.txn});

  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rows = <(String, String)>[
      if (txn.payeeVpa != null) ('UPI ID', txn.payeeVpa!),
      if (txn.upiRef != null) ('UPI reference', txn.upiRef!),
      if (txn.upiApp != null) ('Detected from', txn.upiApp!),
      ('Captured from', switch (txn.source) {
        TxnSource.manual => 'Added manually',
        TxnSource.scanPay => 'Scan & Pay',
        TxnSource.notification => 'Payment notification',
        TxnSource.sms => 'Bank SMS',
        TxnSource.ocr => 'Screenshot',
        TxnSource.statement => 'Bank statement',
      }),
    ];
    return Group(
      dividerIndent: 16,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(child: Text(label, style: t.bodySmall)),
                const SizedBox(width: 12),
                Flexible(
                  child: SelectableText(
                    value,
                    textAlign: TextAlign.end,
                    style: t.bodyMedium?.copyWith(fontFeatures: kTabular),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
