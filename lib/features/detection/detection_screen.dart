import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../transactions/to_categorize_screen.dart';
import 'detected_payment.dart';
import 'detection_service.dart';

/// Turn on automatic recording of money credited and debited (bank SMS and
/// UPI app notifications), import past bank SMS, and test a message.
class DetectionScreen extends ConsumerStatefulWidget {
  const DetectionScreen({super.key});

  @override
  ConsumerState<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends ConsumerState<DetectionScreen> with WidgetsBindingObserver {
  final _sample = TextEditingController();
  String? _testResult;

  /// Set when Android stopped showing the SMS permission dialog.
  bool _smsBlocked = false;
  bool _askingSms = false;
  bool _importing = false;
  String? _importResult;
  int _importedCount = 0;

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

  Future<void> _requestSms() async {
    setState(() => _askingSms = true);
    final result = await _service.requestSmsPermission();
    if (!mounted) return;
    setState(() {
      _askingSms = false;
      _smsBlocked = result == SmsPermissionResult.blocked;
    });
    ref.invalidate(detectionStatusProvider);
    if (result == SmsPermissionResult.granted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bank SMS will be recorded from now on. Import past messages below.'),
      ));
    }
  }

  Future<void> _import(int days) async {
    setState(() {
      _importing = true;
      _importResult = null;
    });
    String message;
    var added = 0;
    try {
      added = await ref.read(detectionSyncProvider).importSms(days);
      message = added == 0
          ? 'No new payments found in the last $days days. Payments already in the app are skipped.'
          : added == 1
              ? 'Added 1 payment from the last $days days.'
              : 'Added $added payments from the last $days days.';
      refreshAll(ref);
    } catch (e) {
      message = 'Could not read your messages: $e';
    }
    if (!mounted) return;
    setState(() {
      _importing = false;
      _importResult = message;
      _importedCount = added;
    });
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
      if (p.account != null) 'Account or card ending: ${p.account}',
      'Method: ${switch (p.mode) { 'card' => 'Card', 'bank' => 'Bank transfer', _ => 'UPI' }}',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(detectionStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Record payments automatically')),
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
    final restrictedTip = s.sdk >= 33;

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
            title: Text(s.isWorking ? 'Recording is on' : 'Recording is off'),
            subtitle: Text(
              s.isWorking
                  ? 'Money credited and debited is added for you. You pick the category.'
                  : 'Finish step 1 below to record payments automatically.',
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Set up', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _StepTile(
          number: 1,
          done: s.smsPermission,
          title: 'Read bank SMS',
          subtitle: s.smsPermission
              ? 'Allowed. Every credit and debit SMS from your bank is recorded.'
              : 'Recommended. Records every credit and debit from your bank, for any UPI '
                  'app, card or transfer, even when message notifications are muted.',
          action: s.smsPermission
              ? null
              : FilledButton(
                  onPressed: _askingSms ? null : (_smsBlocked ? _service.openAppInfo : _requestSms),
                  child: Text(_smsBlocked ? 'Open App info' : 'Allow'),
                ),
        ),
        if (!s.smsPermission && (_smsBlocked || restrictedTip))
          _Tip(
            text: _smsBlocked
                ? 'Android is not showing the permission request. Open App info, tap ⋮ '
                    '(top right) and choose "Allow restricted settings" if you see it, then '
                    'go to Permissions > SMS and choose Allow.'
                : 'If Android says "Restricted setting", open App info, tap ⋮ (top right), '
                    'choose "Allow restricted settings", then tap Allow here again. Android '
                    'asks for this for apps installed from an APK file.',
            action: _smsBlocked
                ? null
                : TextButton(onPressed: _service.openAppInfo, child: const Text('Open App info')),
          ),
        _StepTile(
          number: 2,
          done: s.accessEnabled,
          title: 'Read payment app notifications',
          subtitle: s.accessEnabled
              ? 'Allowed. Google Pay, PhonePe and other UPI apps add the shop or person name.'
              : 'Optional. Adds names from Google Pay, PhonePe, Paytm and others, and works '
                  'as a backup if SMS reading is not allowed.',
          action: s.accessEnabled
              ? null
              : OutlinedButton(
                  onPressed: _service.openAccessSettings,
                  child: const Text('Allow'),
                ),
        ),
        if (!s.accessEnabled && restrictedTip)
          _Tip(
            text: 'Is the switch greyed out? Open App info, tap ⋮ (top right), choose '
                '"Allow restricted settings", then tap Allow here again.',
            action: TextButton(onPressed: _service.openAppInfo, child: const Text('Open App info')),
          ),
        _StepTile(
          number: 3,
          done: s.canNotify,
          title: 'Show category buttons',
          subtitle: s.canNotify
              ? 'After each payment you get a notification to pick its category in one tap.'
              : 'Without this, new payments still appear in "To categorize".',
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
        if (s.canNotify && !s.alertsPopUp)
          _Tip(
            text: 'Payment alerts are set not to pop up. Turn on "Pop on screen" for '
                'Payment alerts so you can pick a category the moment you pay.',
            action: TextButton(
              onPressed: _service.openAlertSettings,
              child: const Text('Open alert settings'),
            ),
          ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: s.enabled,
          onChanged: _setEnabled,
          title: const Text('Record payments automatically'),
          subtitle: const Text('Turn off to pause recording without removing permissions.'),
        ),
        const Divider(height: 32),
        Row(
          children: [
            Expanded(child: Text('Recent message checks', style: theme.textTheme.titleMedium)),
            TextButton(
              onPressed: () => ref.invalidate(detectionStatusProvider),
              child: const Text('Refresh'),
            ),
          ],
        ),
        Text(
          'Payments recorded, and money messages that were skipped. Other notifications '
          'are not listed.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        _CheckLog(checks: s.checks, smsAllowed: s.smsPermission),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s.keepSkippedText,
          onChanged: (v) async {
            await _service.setKeepSkippedText(v);
            ref.invalidate(detectionStatusProvider);
          },
          title: const Text('Show the text of skipped messages'),
          subtitle: const Text(
            'Helps find out why a payment was missed. Kept only on this phone; OTP and PIN '
            'messages are never kept. Turning it off deletes the text.',
          ),
        ),
        const Divider(height: 32),
        Text('Import past bank SMS', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          s.smsPermission
              ? 'Adds credits and debits already in your messages. Payments that are '
                  'already in the app, or that you deleted, are skipped.'
              : 'Allow "Read bank SMS" above to import credits and debits already in your messages.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in const [7, 30, 90])
              OutlinedButton(
                onPressed: s.smsPermission && !_importing ? () => _import(days) : null,
                child: Text('Last $days days'),
              ),
          ],
        ),
        if (_importing)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(),
          ),
        if (_importResult != null) ...[
          const SizedBox(height: 12),
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_importResult!),
                  if (_importedCount > 0)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ToCategorizeScreen()),
                        ),
                        child: const Text('Choose categories'),
                      ),
                    )
                  else
                    const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
        const Divider(height: 32),
        Text('How it works', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const _InfoRow(
          icon: Icons.sms_outlined,
          text: 'Only messages from bank sender IDs (like AX-HDFCBK) are read. Messages from '
              'people, OTPs, offers, failed payments and reminders are ignored.',
        ),
        const _InfoRow(
          icon: Icons.swap_vert,
          text: '"Debited", "spent", "paid" and "withdrawn" count as money out. "Credited", '
              '"received" and "refund" count as money in.',
        ),
        const _InfoRow(
          icon: Icons.merge_type,
          text: 'If the same payment shows up in an SMS and in a UPI app, it is saved once.',
        ),
        _InfoRow(
          icon: Icons.battery_saver_outlined,
          text: 'Battery tip: some phones stop apps in the background, so SMS are missed. On '
              'Samsung open Settings > Battery > Background usage limits > Never sleeping '
              'apps and add Dripless. On any phone, App info > Battery > Unrestricted helps.',
          action: TextButton(onPressed: _service.openAppInfo, child: const Text('Open App info')),
        ),
        const _InfoRow(
          icon: Icons.lock_outline,
          text: 'Only the amount, date, name, UPI ID, reference and last digits of the account '
              'are kept. Message text is not stored, and nothing leaves your phone.',
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

/// Help text indented under a setup step.
class _Tip extends StatelessWidget {
  const _Tip({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 0, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: Theme.of(context).textTheme.bodySmall),
          if (action != null) action!,
        ],
      ),
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
  const _InfoRow({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text),
                if (action != null) action!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the app did with the last few messages, so it is clear whether SMS
/// are arriving at all and why one was skipped.
class _CheckLog extends StatelessWidget {
  const _CheckLog({required this.checks, required this.smsAllowed});

  final List<MessageCheck> checks;
  final bool smsAllowed;

  static String _outcome(MessageCheck c) {
    final amount = c.amountPaise == null ? '' : ' ${formatPaise(c.amountPaise!)}';
    final dir = c.isDebit == null ? '' : (c.isDebit! ? ' paid' : ' received');
    return switch (c.outcome) {
      'recorded' => 'Recorded$amount$dir',
      'merged' => 'Same payment as one already recorded$amount',
      'not_payment' => 'Not a completed payment, skipped',
      'not_bank' => 'From a personal number, not read',
      'paused' => 'Recording is paused',
      'save_failed' => 'Could not save into the app, will retry: ${c.message ?? ''}',
      _ => c.outcome,
    };
  }

  static String _channel(String channel) => switch (channel) {
        'sms' => 'SMS',
        'sms_notification' => 'SMS notification',
        'app_notification' => 'App notification',
        'app' => 'Dripless',
        _ => channel,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (checks.isEmpty) {
      return Text(
        smsAllowed
            ? 'No messages checked since the app was installed. When a bank SMS arrives it '
                'shows up here within a second. If a bank SMS arrives and nothing appears, '
                'your phone is stopping the app in the background: see the battery tip below.'
            : 'Nothing yet. Allow "Read bank SMS" above first.',
        style: t.bodySmall,
      );
    }
    return Column(
      children: [
        for (final c in checks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    c.outcome == 'recorded' || c.outcome == 'merged'
                        ? Icons.check_circle_outline
                        : Icons.remove_circle_outline,
                    size: 18,
                    color: c.outcome == 'recorded' || c.outcome == 'merged'
                        ? scheme.primary
                        : scheme.outline,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_outcome(c), style: t.bodyMedium),
                      Text(
                        '${c.source}, ${_channel(c.channel)}, ${formatDateTime(c.time)}',
                        style: t.bodySmall,
                      ),
                      if (c.text != null)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SelectableText(c.text!, style: t.bodySmall),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
