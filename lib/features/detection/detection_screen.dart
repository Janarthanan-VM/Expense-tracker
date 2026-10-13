import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import 'detected_payment.dart';
import 'detection_service.dart';

/// Turn on automatic detection of UPI payments and check that it works.
class DetectionScreen extends ConsumerStatefulWidget {
  const DetectionScreen({super.key});

  @override
  ConsumerState<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends ConsumerState<DetectionScreen> with WidgetsBindingObserver {
  final _sample = TextEditingController();
  String? _testResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sample.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user comes back from Android settings.
    if (state == AppLifecycleState.resumed) ref.invalidate(detectionStatusProvider);
  }

  DetectionService get _service => ref.read(detectionServiceProvider);

  Future<void> _setEnabled(bool value) async {
    await _service.setEnabled(value);
    ref.invalidate(detectionStatusProvider);
  }

  Future<void> _test() async {
    final text = _sample.text.trim();
    if (text.isEmpty) return;
    final DetectedPayment? p;
    try {
      p = await _service.testParse(text);
    } catch (e) {
      if (mounted) setState(() => _testResult = 'Could not check the message: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _testResult = p == null
        ? 'Not recognised as a completed payment. Messages about OTPs, requests, '
            'failed payments and reminders are ignored on purpose.'
        : _describe(p));
  }

  String _describe(DetectedPayment p) {
    final amount = formatPaise(p.amountPaise ?? 0);
    final who = p.payeeName ?? p.payeeVpa;
    final lines = <String>[
      if (p.isDebit == true) 'Paid $amount${who != null ? ' to $who' : ''}'
      else 'Received $amount${who != null ? ' from $who' : ''}',
      if (p.payeeVpa != null && p.payeeName != null) 'UPI ID: ${p.payeeVpa}',
      if (p.upiRef != null) 'UPI reference: ${p.upiRef}',
      'Method: ${switch (p.mode) { 'card' => 'Card', 'bank' => 'Bank transfer', _ => 'UPI' }}',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(detectionStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Detect UPI payments')),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not check detection: $e')),
        data: (s) => s.supported ? _body(context, s) : _unsupported(context),
      ),
    );
  }

  Widget _unsupported(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Automatic detection needs Android. You can still add payments yourself.',
            textAlign: TextAlign.center,
          ),
        ),
      );

  Widget _body(BuildContext context, DetectionStatus s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card.filled(
          color: s.isWorking ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          child: ListTile(
            leading: Icon(
              s.isWorking ? Icons.check_circle : Icons.notifications_off_outlined,
              color: s.isWorking ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            ),
            title: Text(s.isWorking ? 'Detection is on' : 'Detection is off'),
            subtitle: Text(
              s.isWorking
                  ? 'UPI payments are recorded from your payment apps and bank SMS.'
                  : 'Finish the steps below to record UPI payments automatically.',
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Set up', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _StepTile(
          number: 1,
          done: s.accessEnabled,
          title: 'Allow notification access',
          subtitle: s.accessEnabled
              ? 'Allowed'
              : 'Lets the app read payment messages from Google Pay, PhonePe and your bank SMS.',
          action: s.accessEnabled
              ? null
              : FilledButton(
                  onPressed: _service.openAccessSettings,
                  child: const Text('Allow'),
                ),
        ),
        if (!s.accessEnabled && s.sdk >= 33)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 0, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Is the switch greyed out? Android blocks this for apps installed '
                  'outside the Play Store until you allow it: open App info, tap ⋮ '
                  '(top right), choose "Allow restricted settings", then tap Allow here again.',
                  style: theme.textTheme.bodySmall,
                ),
                TextButton(
                  onPressed: _service.openAppInfo,
                  child: const Text('Open App info'),
                ),
              ],
            ),
          ),
        _StepTile(
          number: 2,
          done: s.canNotify,
          title: 'Show category buttons',
          subtitle: s.canNotify
              ? 'After each payment you get a notification to pick its category in one tap.'
              : 'Without this, detected payments still appear in "To categorize".',
          action: s.canNotify
              ? null
              : OutlinedButton(
                  onPressed: () async {
                    await _service.requestNotificationPermission();
                    ref.invalidate(detectionStatusProvider);
                  },
                  child: const Text('Allow'),
                ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: s.enabled,
          onChanged: _setEnabled,
          title: const Text('Record UPI payments automatically'),
          subtitle: const Text('Turn off to pause detection without removing access.'),
        ),
        const Divider(height: 32),
        Text('Where payments are read from', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const _InfoRow(
          icon: Icons.sms_outlined,
          text: 'Bank SMS shown by your messages app (Google Messages, Samsung, Mi and others). '
              'Works with every UPI app, so keep message notifications turned on.',
        ),
        const _InfoRow(
          icon: Icons.apps,
          text: 'Google Pay, PhonePe, Paytm, BHIM, CRED, Amazon Pay and MobiKwik notifications.',
        ),
        const _InfoRow(
          icon: Icons.merge_type,
          text: 'If the same payment appears in both, it is saved once.',
        ),
        const _InfoRow(
          icon: Icons.lock_outline,
          text: 'Only payment messages are used. Other notifications, OTPs and chats are ignored '
              'and never stored. Nothing leaves your phone.',
        ),
        const Divider(height: 32),
        Text('Check a message', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Paste a bank SMS or payment notification to see what the app reads from it.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _sample,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Rs.250.00 debited from A/c XX1234 to VPA shop@okaxis. UPI Ref 426512345678',
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(onPressed: _test, child: const Text('Check message')),
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(_testResult!),
            ),
          ),
        ],
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.number,
    required this.done,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final int number;
  final bool done;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: done ? scheme.primary : scheme.surfaceContainerHighest,
            foregroundColor: done ? scheme.onPrimary : scheme.onSurfaceVariant,
            child: done ? const Icon(Icons.check, size: 18) : Text('$number'),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
