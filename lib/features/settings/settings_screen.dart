import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/ui.dart';
import '../detection/detection_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final detection = ref.watch(detectionStatusProvider).valueOrNull;
    final recording = detection?.isWorking ?? false;

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
          const SectionHeader('Coming soon'),
          Group(
            children: [
              _SettingRow(
                icon: Icons.backup_outlined,
                color: p.muted,
                title: 'Backup and restore',
                subtitle: 'An encrypted backup file you can keep anywhere',
              ),
              _SettingRow(
                icon: Icons.qr_code_scanner,
                color: p.muted,
                title: 'Scan & Pay',
                subtitle: 'Scan a UPI QR here and pay with your UPI app',
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
                icon: Icons.info_outline,
                color: p.muted,
                title: 'Dripless',
                subtitle: 'Version 0.5.1',
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
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
