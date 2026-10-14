import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../detection/detection_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detection = ref.watch(detectionStatusProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Record payments automatically'),
            subtitle: Text(
              detection == null
                  ? 'Money credited and debited from bank SMS and UPI apps'
                  : detection.isWorking
                      ? 'On'
                      : 'Off. Tap to set up',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DetectionScreen()),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.backup_outlined),
            title: Text('Backup and restore'),
            subtitle: Text('Save an encrypted backup file to your phone or Google Drive. Coming soon.'),
            enabled: false,
          ),
          const ListTile(
            leading: Icon(Icons.qr_code_scanner),
            title: Text('Scan & Pay'),
            subtitle: Text('Scan a UPI QR here and pay with your UPI app. Coming soon.'),
            enabled: false,
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Your data stays on this phone'),
            subtitle: Text('Stored in an encrypted database. Nothing is uploaded.'),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('0.4.0'),
          ),
        ],
      ),
    );
  }
}
