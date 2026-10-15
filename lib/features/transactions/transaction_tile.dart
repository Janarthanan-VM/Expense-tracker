import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/ui.dart';
import '../../core/utils/formatters.dart';
import '../categories/category.dart';
import 'payment_mode_ui.dart';
import 'txn.dart';

/// One row in any transaction list. Sits inside a [Group].
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.txn,
    required this.category,
    this.onTap,
    this.onLongPress,
    this.showDate = false,
  });

  final Txn txn;
  final TxnCategory? category;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final isDebit = txn.type == TxnType.debit;
    final cat = category;
    final isFailed = txn.status == TxnStatus.failed;

    final title = txn.payeeLabel ?? cat?.name ?? (isDebit ? 'Payment' : 'Money received');
    final when = showDate ? formatDateTime(txn.txnTime) : formatTime(txn.txnTime);

    final Widget subtitle;
    if (isFailed) {
      subtitle = Text('Failed', style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error));
    } else if (txn.status == TxnStatus.pending) {
      subtitle = Text(
        'Waiting for bank confirmation',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.bodySmall?.copyWith(color: p.attention),
      );
    } else if (cat == null) {
      subtitle = Text(
        'Choose category',
        style: t.bodySmall?.copyWith(color: p.attention, fontWeight: FontWeight.w700),
      );
    } else if (!txn.isReviewed) {
      subtitle = Text(
        'Suggested: ${cat.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.bodySmall?.copyWith(color: p.attention),
      );
    } else {
      subtitle = Text(cat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall);
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconTile(
              icon: cat?.icon ?? (isDebit ? Icons.north_east : Icons.south_west),
              color: cat?.color ?? p.faint,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall?.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  subtitle,
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AmountText(
                  text: '${isDebit ? '−' : '+'}${formatPaise(txn.amountPaise)}',
                  isIncome: !isDebit,
                  struck: isFailed,
                  style: t.titleSmall?.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(txn.paymentMode.icon, size: 13, color: p.faint),
                    const SizedBox(width: 4),
                    Text(when, style: t.bodySmall?.copyWith(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
