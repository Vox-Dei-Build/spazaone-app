import 'package:flutter/material.dart';

import '../services/analytics_event.dart';
import '../services/consent_service.dart';
import '../services/crash_service.dart';
import '../services/telemetry_service.dart';

/// First-run consent modal.
///
/// Shown the first time we have a `BuildContext` after `main()` has finished
/// initialising, IF [ConsentState.hasDecided] is false.
///
/// POPIA stance:
///   * Crash reports default ON. Rationale: they contain technical metadata
///     only (no message bodies, no contact data), and the modal explicitly
///     surfaces the toggle so the user can opt out before dismissing.
///   * Product analytics and session replay default OFF. The user has to
///     opt in.
///   * The user cannot dismiss the modal without making a choice (no
///     barrier-tap to close, system back is intercepted by [PopScope]).
class ConsentModal extends StatefulWidget {
  const ConsentModal({super.key});

  /// Shows the modal and returns once the user has made a choice.
  /// Safe to call multiple times -- subsequent calls return immediately if
  /// consent has already been decided.
  static Future<void> showIfNeeded(BuildContext context) async {
    if (ConsentService.instance.state.hasDecided) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ConsentModal(),
    );
  }

  @override
  State<ConsentModal> createState() => _ConsentModalState();
}

class _ConsentModalState extends State<ConsentModal> {
  late bool _analytics;
  late bool _replay;
  late bool _crash;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = ConsentService.instance.state;
    _analytics = initial.analytics; // false on first run
    _replay = initial.replay;       // false on first run
    _crash = initial.crash;         // true  on first run
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

    // The very first event after consent records the decision itself, so we
    // can audit consent rates in the dashboard.
    await TelemetryService.instance.capture(
      ConsentDecided(
        analytics: _analytics,
        replay: _replay,
        crash: _crash,
        surface: 'first_run_modal',
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: AlertDialog(
        title: const Text('Help us improve Pasella'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'We collect a small amount of data to keep the app stable and '
                'understand which features merchants find useful. You stay in '
                'control -- change these any time in Settings -> Privacy.',
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Crash reports'),
                subtitle: const Text(
                  'Send technical details when the app crashes so we can fix it.',
                ),
                value: _crash,
                onChanged: _saving ? null : (v) => setState(() => _crash = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Product analytics'),
                subtitle: const Text(
                  'Anonymous usage events (no message contents, no contacts).',
                ),
                value: _analytics,
                onChanged:
                    _saving ? null : (v) => setState(() => _analytics = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Session replay'),
                subtitle: const Text(
                  'Masked recordings of your screens so we can debug rough edges. '
                  'All text and images are blurred. Requires product analytics.',
                ),
                value: _replay && _analytics,
                onChanged: (_saving || !_analytics)
                    ? null
                    : (v) => setState(() => _replay = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    setState(() {
                      _analytics = false;
                      _replay = false;
                      _crash = false;
                    });
                    _save();
                  },
            child: const Text('Reject all'),
          ),
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    setState(() {
                      _analytics = true;
                      _replay = true;
                      _crash = true;
                    });
                    _save();
                  },
            child: const Text('Accept all'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
