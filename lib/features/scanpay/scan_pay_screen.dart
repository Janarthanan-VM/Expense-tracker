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
import '../transactions/txn.dart';
import 'qr_scanner_page.dart';
import 'upi_qr.dart';

Future<void> openScanPay(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScanPayScreen()),
    );

/// Scan a UPI QR, choose the category, pay with any UPI app. The payment is
/// recorded straight away; the bank SMS later fills in the reference.
class ScanPayScreen extends ConsumerStatefulWidget {
  const ScanPayScreen({super.key, this.initialQr});

  /// Skips the scanner (used by tests and by "scan again").
  final String? initialQr;

  @override
  ConsumerState<ScanPayScreen> createState() => _ScanPayScreenState();
}

class _ScanPayScreenState extends ConsumerState<ScanPayScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  UpiQr? _qr;
  String? _categoryId;
  bool _remember = false;
  String? _error;
  String? _amountError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialQr != null) {
        _useQr(widget.initialQr!);
      } else {
        _scan();
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final raw = await scanQrCode(context);
    if (!mounted) return;
    if (raw == null) {
      // Backed out of the scanner before scanning anything: leave.
      if (_qr == null) Navigator.of(context).maybePop();
      return;
    }
    await _useQr(raw);
  }

  Future<void> _useQr(String raw) async {
    final qr = UpiQr.parse(raw);
    if (qr == null) {
      setState(() {
        _qr = null;
        _error = 'This QR code is not a UPI payment code.';
      });
      return;
    }
    final categories = ref.read(categoryMapProvider);
    final remembered = await ref
        .read(txnRepoProvider)
        .rememberedCategory(type: TxnType.debit, vpa: qr.vpa, name: qr.name);
    final suggested = qr.suggestedCategoryId;
    if (!mounted) return;
    setState(() {
      _qr = qr;
      _error = null;
      _amountError = null;
      _amount.text = qr.amountPaise == null ? '' : paiseToInput(qr.amountPaise!);
      _note.text = qr.note ?? '';
      _categoryId = remembered ??
          (suggested != null && categories[suggested]?.isHidden == false ? suggested : null);
    });
  }

  Future<void> _pickCategory() async {
    final qr = _qr;
    if (qr == null) return;
    final result = await showCategoryPicker(
      context,
      categories: ref.read(categoriesProvider).valueOrNull ?? const <TxnCategory>[],
      type: TxnType.debit,
      selectedId: _categoryId,
      payeeLabel: qr.name ?? qr.vpa,
    );
    if (result == null) return;
    setState(() {
      _categoryId = result.categoryId;
      _remember = result.remember;
    });
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pay() async {
    final qr = _qr;
    if (qr == null) return;
    final paise = qr.amountPaise ?? parseRupeesToPaise(_amount.text);
    if (paise == null) {
      setState(() => _amountError = 'Enter an amount above ₹0');
      return;
    }
    setState(() => _busy = true);

    final repo = ref.read(txnRepoProvider);
    final now = DateTime.now();
    final note = _note.text.trim();
    final txn = Txn(
      id: const Uuid().v4(),
      amountPaise: paise,
      type: TxnType.debit,
      status: TxnStatus.pending,
      source: TxnSource.scanPay,
      paymentMode: PaymentMode.upi,
      categoryId: _categoryId,
      categorySource: _categoryId == null ? null : CategorySource.user,
      isReviewed: _categoryId != null,
      payeeName: qr.name,
      payeeVpa: qr.vpa,
      note: note.isEmpty ? null : note,
      txnTime: now,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await repo.add(txn);
      if (_remember && _categoryId != null) {
        await repo.setCategory(txn, _categoryId!, rememberForPayee: true);
      }
    } catch (e) {
      setState(() => _busy = false);
      _toast('Could not save the payment: $e');
      return;
    }

    ({int resultCode, String? response}) reply;
    try {
      reply = await ref.read(platformActionsProvider).payUpi(qr.payLink(amountPaise: paise));
    } on PlatformException catch (e) {
      await repo.delete(txn.id);
      refreshAll(ref);
      setState(() => _busy = false);
      _toast(e.code == 'no_upi_app'
          ? 'No UPI app found. Install Google Pay, PhonePe, Paytm or BHIM.'
          : 'Could not open a UPI app: ${e.message ?? e.code}');
      return;
    }
    if (!mounted) return;

    final outcome = UpiResponse.parse(reply.response);
    final who = qr.name ?? qr.vpa;
    switch (outcome.result) {
      case UpiResult.success:
        await repo.setStatus(txn.id, TxnStatus.success, upiRef: outcome.reference);
        refreshAll(ref);
        _toast('Paid ${formatPaise(paise)} to $who');
        if (mounted) Navigator.of(context).pop();
        return;
      case UpiResult.failure:
        await repo.delete(txn.id);
        refreshAll(ref);
        setState(() => _busy = false);
        _toast('The payment failed. Nothing was recorded.');
        return;
      case UpiResult.submitted:
        refreshAll(ref);
        _toast('Your bank is still processing it. Dripless updates it when the bank SMS arrives.');
        if (mounted) Navigator.of(context).pop();
        return;
      case UpiResult.unknown:
        final paid = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Did the payment go through?'),
            content: Text(
              'Your UPI app did not say. Did ${formatPaise(paise)} reach $who?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, paid')),
            ],
          ),
        );
        if (paid == true) {
          await repo.setStatus(txn.id, TxnStatus.success);
          refreshAll(ref);
          _toast('Recorded ${formatPaise(paise)} to $who');
          if (mounted) Navigator.of(context).pop();
        } else {
          await repo.delete(txn.id);
          refreshAll(ref);
          if (mounted) setState(() => _busy = false);
          _toast('Nothing was recorded. If money did leave, the bank SMS will add it.');
        }
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final qr = _qr;
    final category = ref.watch(categoryMapProvider)[_categoryId];

    return Scaffold(
      appBar: AppBar(title: const Text('Scan & Pay')),
      body: qr == null
          ? (_error == null
              ? const SizedBox.shrink()
              : EmptyState(
                  icon: Icons.qr_code_2,
                  title: _error!,
                  action: FilledButton.icon(
                    onPressed: _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan again'),
                  ),
                ))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const SizedBox(height: 12),
                Center(child: IconTile(icon: Icons.storefront_outlined, color: p.moneyIn, size: 56)),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kGutter),
                  child: Column(
                    children: [
                      Text(
                        qr.name ?? qr.vpa,
                        textAlign: TextAlign.center,
                        style: t.titleLarge,
                      ),
                      if (qr.name != null) ...[
                        const SizedBox(height: 4),
                        Text(qr.vpa, style: t.bodySmall, textAlign: TextAlign.center),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (qr.amountPaise != null)
                  Column(
                    children: [
                      Text(
                        formatPaise(qr.amountPaise!),
                        style: t.displayMedium?.copyWith(fontFeatures: kTabular),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline, size: 14, color: p.muted),
                          const SizedBox(width: 4),
                          Text('Amount set by the QR code', style: t.bodySmall),
                        ],
                      ),
                    ],
                  )
                else
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
                              child: TextField(
                                controller: _amount,
                                autofocus: true,
                                textAlign: TextAlign.center,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                                style: t.displayMedium?.copyWith(fontFeatures: kTabular),
                                onChanged: (_) {
                                  if (_amountError != null) setState(() => _amountError = null);
                                },
                                decoration: InputDecoration(
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  hintText: '0',
                                  hintStyle: t.displayMedium?.copyWith(color: p.faint),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
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
                const SizedBox(height: 28),
                Group(
                  children: [
                    InkWell(
                      onTap: _busy ? null : _pickCategory,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            IconTile(
                              icon: category?.icon ?? Icons.label_outline,
                              color: category?.color ?? p.muted,
                              size: 36,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                category?.name ?? 'Choose category',
                                style: t.bodyLarge?.copyWith(
                                  color: category == null ? p.attention : p.ink,
                                  fontWeight: category == null ? FontWeight.w700 : null,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right, color: p.faint),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          IconTile(icon: Icons.notes_outlined, color: p.muted, size: 36),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _note,
                              textCapitalization: TextCapitalization.sentences,
                              style: t.bodyLarge,
                              decoration: InputDecoration(
                                hintText: 'Note',
                                hintStyle: t.bodyLarge?.copyWith(color: p.faint),
                                filled: false,
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(kGutter + 4, 14, kGutter, 0),
                  child: Text(
                    'You confirm and enter your UPI PIN in your UPI app. Dripless never sees your PIN.',
                    style: t.bodySmall,
                  ),
                ),
                Center(
                  child: TextButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text('Scan a different code'),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: qr == null
          ? null
          : SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  kGutter,
                  8,
                  kGutter,
                  12 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _amount,
                  builder: (context, value, _) {
                    final paise = qr.amountPaise ?? parseRupeesToPaise(value.text);
                    return FilledButton(
                      onPressed: _busy ? null : _pay,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                      child: Text(_busy
                          ? 'Waiting for your UPI app…'
                          : paise == null
                              ? 'Pay'
                              : 'Pay ${formatPaise(paise)}'),
                    );
                  },
                ),
              ),
            ),
    );
  }
}
