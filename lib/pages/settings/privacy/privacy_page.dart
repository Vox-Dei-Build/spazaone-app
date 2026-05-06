import 'package:flutter/material.dart';

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
      backgroundColor: Colors.grey.shade50,
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
  late bool _replay = widget.state.replay;
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
      _replay = widget.state.replay;
      _crash = widget.state.crash;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    await ConsentService.instance.recordDecision(
      analytics: _analytics,
      replay: _replay,
      crash: _crash,
    );
    await CrashService.instance.applyConsent(ConsentService.instance.state);
    await TelemetryService.instance.applyConsent(ConsentService.instance.state);
    await TelemetryService.instance.capture(
      ConsentDecided(
        analytics: _analytics,
        replay: _replay,
        crash: _crash,
        surface: 'settings_privacy',
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Privacy settings updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _analytics != widget.state.analytics ||
        _replay != widget.state.replay ||
        _crash != widget.state.crash;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose what data Pasella may collect to keep the app stable and '
            'understand how merchants use it. Changes apply immediately.',
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Crash reports'),
            subtitle: const Text(
              'Send technical details when the app crashes so we can fix it.',
            ),
            value: _crash,
            onChanged: _saving ? null : (v) => setState(() => _crash = v),
          ),
          SwitchListTile(
            title: const Text('Product analytics'),
            subtitle: const Text(
              'Anonymous usage events. No message contents, no contacts.',
            ),
            value: _analytics,
            onChanged: _saving
                ? null
                : (v) => setState(() {
                      _analytics = v;
                      // Replay is meaningless without analytics.
                      if (!v) _replay = false;
                    }),
          ),
          SwitchListTile(
            title: const Text('Session replay'),
            subtitle: const Text(
              'Masked recordings of your screens to debug rough edges. All text '
              'and images are blurred. Requires product analytics.',
            ),
            value: _replay && _analytics,
            onChanged: (_saving || !_analytics)
                ? null
                : (v) => setState(() => _replay = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_saving || !dirty) ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Save'),
          ),
          if (widget.state.decidedAt != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last updated ${widget.state.decidedAt!.toLocal()}',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
