import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.backup_outlined),
            title: Text('Backup and restore'),
            subtitle: Text('Save an encrypted backup file to your phone or Google Drive. Coming next.'),
            enabled: false,
          ),
          ListTile(
            leading: Icon(Icons.notifications_active_outlined),
            title: Text('Detect UPI payments automatically'),
            subtitle: Text('Record PhonePe and Google Pay payments from notifications. Coming soon.'),
            enabled: false,
          ),
          ListTile(
            leading: Icon(Icons.qr_code_scanner),
            title: Text('Scan & Pay'),
            subtitle: Text('Scan a UPI QR here and pay with your UPI app. Coming soon.'),
            enabled: false,
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Your data stays on this phone'),
            subtitle: Text('Stored in an encrypted database. Nothing is uploaded.'),
          ),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('0.1.1'),
          ),
        ],
      ),
    );
  }
}
