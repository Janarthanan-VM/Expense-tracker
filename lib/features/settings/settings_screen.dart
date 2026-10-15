import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/ui.dart';
import '../../core/utils/formatters.dart';
import '../backup/backup_screen.dart';
import '../detection/detection_screen.dart';
import '../scanpay/scan_pay_screen.dart';
import 'payee_rules_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final detection = ref.watch(detectionStatusProvider).valueOrNull;
    final recording = detection?.isWorking ?? false;
    final lastBackup = ref.watch(lastBackupProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const SectionHeader('Recording', padding: EdgeInsets.fromLTRB(kGutter, 8, kGutter, 10)),
          Group(
            children: [
              _SettingRow(
                icon: Icons.sms_outlined,
                color: p.moneyIn,
                title: 'Record payments automatically',
                subtitle: detection == null
                    ? 'Credits and debits from bank SMS and UPI apps'
                    : recording
                        ? 'On'
                        : 'Off. Tap to set up',
                trailing: recording
                    ? null
                    : Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                      ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DetectionScreen()),
                ),
              ),
            ],
          ),
          const SectionHeader('Pay and organise'),
          Group(
            children: [
              _SettingRow(
                icon: Icons.qr_code_scanner,
                color: p.moneyIn,
                title: 'Scan & Pay',
                subtitle: 'Scan a UPI QR, pay with your UPI app, recorded straight away',
                onTap: () => openScanPay(context),
              ),
              _SettingRow(
                icon: Icons.person_search_outlined,
                color: p.muted,
                title: 'Remembered payees',
                subtitle: 'Payees that always get the same category',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PayeeRulesScreen()),
                ),
              ),
            ],
          ),
          const SectionHeader('Your data'),
          Group(
            children: [
              _SettingRow(
                icon: Icons.backup_outlined,
                color: lastBackup == null ? p.attention : p.muted,
                title: 'Backup and restore',
                subtitle: lastBackup == null
                    ? 'No backup yet. Save one to Google Drive or your phone'
                    : 'Last backup ${formatDateTime(lastBackup)}',
                trailing: lastBackup == null
                    ? Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                      )
                    : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BackupScreen()),
                ),
              ),
            ],
          ),
          const SectionHeader('About'),
          Group(
            children: [
              _SettingRow(
                icon: Icons.lock_outline,
                color: p.muted,
                title: 'Your data stays on this phone',
                subtitle: 'Stored in an encrypted database. Nothing is uploaded.',
              ),
              _SettingRow(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.tileRadius),
                  child: Image.asset('assets/images/logo.png', width: 40, height: 40),
                ),
                icon: Icons.info_outline,
                color: p.muted,
                title: 'Dripless',
                subtitle: '0.8.0',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.leading,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Replaces the icon tile (used for the app logo).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          leading ?? IconTile(icon: icon, color: color),
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
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: p.faint),
          ],
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}
