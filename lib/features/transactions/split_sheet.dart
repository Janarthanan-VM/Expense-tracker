import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/ui.dart';
import '../../core/utils/formatters.dart';

class SplitResult {
  const SplitResult(this.mySharePaise);

  /// Null means "not split".
  final int? mySharePaise;
}

/// Your share when a bill of [totalPaise] is split equally between [people]
/// (you included). Rounded up to the rupee so friends never owe you paise.
int equalShare(int totalPaise, int people) {
  if (people <= 1) return totalPaise;
  final share = (totalPaise / people).ceil();
  final roundedUp = ((share + 99) ~/ 100) * 100;
  return roundedUp >= totalPaise ? share : roundedUp;
}

/// Asks how a bill is split: equally between some people, or a custom share.
Future<SplitResult?> showSplitSheet(
  BuildContext context, {
  required int totalPaise,
  int? currentShare,
}) =>
    showModalBottomSheet<SplitResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SplitSheet(totalPaise: totalPaise, currentShare: currentShare),
    );

class _SplitSheet extends StatefulWidget {
  const _SplitSheet({required this.totalPaise, this.currentShare});

  final int totalPaise;
  final int? currentShare;

  @override
  State<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends State<_SplitSheet> {
  int _people = 2;
  bool _custom = false;
  final _share = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = widget.currentShare;
    if (current != null) {
      // Show the existing split as "equal" when it matches, else as custom.
      final match = [for (var n = 2; n <= 20; n++) n]
          .where((n) => equalShare(widget.totalPaise, n) == current);
      if (match.isNotEmpty) {
        _people = match.first;
      } else {
        _custom = true;
        _share.text = paiseToInput(current);
      }
    }
  }

  @override
  void dispose() {
    _share.dispose();
    super.dispose();
  }

  int? get _myShare =>
      _custom ? parseRupeesToPaise(_share.text) : equalShare(widget.totalPaise, _people);

  void _done() {
    final share = _myShare;
    if (share == null || share >= widget.totalPaise) {
      setState(() => _error = 'Your share must be less than ${formatPaise(widget.totalPaise)}');
      return;
    }
    Navigator.pop(context, SplitResult(share));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final share = _myShare;
    final valid = share != null && share < widget.totalPaise;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Split ${formatPaise(widget.totalPaise)}', style: t.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Only your share counts as your spending. When friends pay you back, '
                'choose "Paid back by friends" as the category.',
                style: t.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Pill(label: 'Equally', selected: !_custom, onTap: () => setState(() => _custom = false)),
                  const SizedBox(width: 8),
                  Pill(label: 'My share', selected: _custom, onTap: () => setState(() => _custom = true)),
                ],
              ),
              const SizedBox(height: 16),
              if (!_custom)
                Row(
                  children: [
                    Expanded(child: Text('People, including you', style: t.bodyLarge)),
                    IconButton.outlined(
                      tooltip: 'Fewer people',
                      onPressed: _people > 2 ? () => setState(() => _people--) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text('$_people', textAlign: TextAlign.center, style: t.titleLarge),
                    ),
                    IconButton.outlined(
                      tooltip: 'More people',
                      onPressed: _people < 20 ? () => setState(() => _people++) : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                )
              else
                TextField(
                  controller: _share,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: const InputDecoration(prefixText: '₹ ', hintText: 'Your share'),
                  onChanged: (_) => setState(() => _error = null),
                ),
              const SizedBox(height: 16),
              if (valid)
                Text.rich(TextSpan(children: [
                  TextSpan(text: 'Your share ', style: t.bodyMedium?.copyWith(color: p.muted)),
                  TextSpan(text: formatPaise(share), style: t.titleMedium),
                  TextSpan(text: '    Friends owe you ', style: t.bodyMedium?.copyWith(color: p.muted)),
                  TextSpan(text: formatPaise(widget.totalPaise - share), style: t.titleMedium?.copyWith(color: p.moneyIn)),
                ])),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.currentShare != null)
                    TextButton(
                      onPressed: () => Navigator.pop(context, const SplitResult(null)),
                      child: const Text('Remove split'),
                    ),
                  const Spacer(),
                  FilledButton(onPressed: _done, child: const Text('Done')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
