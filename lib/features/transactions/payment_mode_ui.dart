import 'package:flutter/material.dart';

import 'txn.dart';

extension PaymentModeIcon on PaymentMode {
  IconData get icon => switch (this) {
        PaymentMode.cash => Icons.payments_outlined,
        PaymentMode.upi => Icons.qr_code_2,
        PaymentMode.card => Icons.credit_card,
        PaymentMode.bank => Icons.account_balance_outlined,
        PaymentMode.other => Icons.more_horiz,
      };
}

/// Row of chips to choose how a payment was made.
class PaymentModeSelector extends StatelessWidget {
  const PaymentModeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final PaymentMode selected;
  final ValueChanged<PaymentMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in PaymentMode.values)
          ChoiceChip(
            avatar: Icon(mode.icon, size: 18),
            label: Text(mode.shortLabel),
            selected: mode == selected,
            showCheckmark: false,
            onSelected: (_) => onChanged(mode),
          ),
      ],
    );
  }
}
