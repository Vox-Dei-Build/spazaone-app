import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../constants/app_urls.dart';
import '../../../services/analytics_event.dart';
import '../../../services/consent_service.dart';
import '../../../services/crash_service.dart';
import '../../../services/telemetry_service.dart';
import '../../../shared/widgets/custom_app_bar.dart';

/// Settings -> Privacy.
///
/// Lets the user revisit the consent decision they made at first launch.
/// Same toggles, same defaults rules, just no "modal" framing.
///
/// Listens to [ConsentService.instance.notifier] so changes from elsewhere
/// (e.g. a future "delete my data" flow) are reflected immediately.
class PrivacyPage extends StatelessWidget {
  static const String id = '/privacy';

  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Privacy'),
      body: SafeArea(
        child: ValueListenableBuilder<ConsentState>(
          valueListenable: ConsentService.instance.notifier,
          builder: (context, state, _) => _PrivacyBody(state: state),
        ),
      ),
    );
  }
}

class _PrivacyBody extends StatefulWidget {
  const _PrivacyBody({required this.state});

  final ConsentState state;

  @override
  State<_PrivacyBody> createState() => _PrivacyBodyState();
}

class _PrivacyBodyState extends State<_PrivacyBody> {
  late bool _analytics = widget.state.analytics;
  late bool _crash = widget.state.crash;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _PrivacyBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reflect external state mutations (e.g. another tab) without losing
    // an in-flight edit. We only sync when the persisted value differs from
    // the value we last saved -- which means the change came from outside.
    if (oldWidget.state != widget.state && !_saving) {
      _analytics = widget.state.analytics;
      _crash = widget.state.crash;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    await ConsentService.instance.recordDecision(
      analytics: _analytics,
      crash: _crash,
    );
    await CrashService.instance.applyConsent(ConsentService.instance.state);
    await TelemetryService.instance.applyConsent(ConsentService.instance.state);
    await TelemetryService.instance.capture(
      ConsentDecided(
        analytics: _analytics,
        replay: false,
        crash: _crash,
        surface: 'settings_privacy',
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Privacy settings updated')));
  }

  @override
  Widget build(BuildContext context) => PrivacySettingsForm(
        analytics: _analytics,
        crash: _crash,
        saving: _saving,
        dirty: _analytics != widget.state.analytics ||
            _crash != widget.state.crash,
        decidedAt: widget.state.decidedAt,
        onAnalyticsChanged: (value) => setState(() => _analytics = value),
        onCrashChanged: (value) => setState(() => _crash = value),
        onSave: _save,
        onOpenPolicy: () async {
          final opened = await launchUrl(
            Uri.parse(AppUrls.privacyPolicy),
            mode: LaunchMode.externalApplication,
          );
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open privacy policy')),
            );
          }
        },
      );
}

/// Controlled presentation; consent persistence stays in the authenticated page.
class PrivacySettingsForm extends StatelessWidget {
  const PrivacySettingsForm({
    super.key,
    required this.analytics,
    required this.crash,
    required this.saving,
    required this.dirty,
    required this.onAnalyticsChanged,
    required this.onCrashChanged,
    required this.onSave,
    required this.onOpenPolicy,
    this.decidedAt,
  });
  final bool analytics;
  final bool crash;
  final bool saving;
  final bool dirty;
  final DateTime? decidedAt;
  final ValueChanged<bool> onAnalyticsChanged;
  final ValueChanged<bool> onCrashChanged;
  final VoidCallback onSave;
  final VoidCallback onOpenPolicy;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Choose what data Spaza One may collect to keep the app stable and '
            'understand how merchants use it. Save to apply your changes.',
          ),
          const SizedBox(height: 24),
          Card(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.all(16),
              title: const Text('Crash reports'),
              subtitle: const Text(
                'Send technical details when the app crashes so we can fix it.',
              ),
              value: crash,
              onChanged: saving ? null : onCrashChanged,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.all(16),
              title: const Text('Product analytics'),
              subtitle: const Text(
                'Usage events linked to your Spaza One account. No message '
                'contents or contact details.',
              ),
              value: analytics,
              onChanged: saving ? null : onAnalyticsChanged,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (saving || !dirty) ? null : onSave,
            child: Text(saving ? 'Saving...' : 'Save'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onOpenPolicy,
            child: const Text('Read the Spaza One Privacy Policy'),
          ),
          if (decidedAt != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last updated ${DateFormat.yMMMd().add_jm().format(decidedAt!.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      );
}
