import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../categories/category.dart';
import 'payment_mode_ui.dart';
import 'txn.dart';

/// One row in any transaction list.
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDebit = txn.type == TxnType.debit;
    final cat = category;

    final title = txn.payeeLabel ??
        cat?.name ??
        (isDebit ? 'Payment' : 'Money received');

    final accent = cat?.color ?? scheme.outline;
    final when = showDate ? formatDateTime(txn.txnTime) : formatTime(txn.txnTime);
    final isFailed = txn.status == TxnStatus.failed;

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: CircleAvatar(
        backgroundColor: accent.withValues(alpha: 0.14),
        foregroundColor: accent,
        child: Icon(cat?.icon ?? Icons.help_outline),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text.rich(
        TextSpan(children: [
          if (cat == null)
            TextSpan(
              text: 'Choose category',
              style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w600),
            )
          else
            TextSpan(text: cat.name),
          if (cat != null && !txn.isReviewed)
            TextSpan(
              text: ' (suggested)',
              style: TextStyle(color: scheme.tertiary),
            ),
          const TextSpan(text: '\n'),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(txn.paymentMode.icon, size: 14, color: scheme.onSurfaceVariant),
            ),
          ),
          TextSpan(text: '${txn.paymentMode.shortLabel}, $when'),
          if (isFailed)
            TextSpan(text: ', failed', style: TextStyle(color: scheme.error)),
        ]),
        maxLines: 2,
      ),
      isThreeLine: true,
      trailing: Text(
        '${isDebit ? '−' : '+'}${formatPaise(txn.amountPaise)}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: isFailed
              ? scheme.outline
              : (isDebit ? AppTheme.expense : AppTheme.income),
          decoration: isFailed ? TextDecoration.lineThrough : null,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
