import 'package:flutter/material.dart';

import '../constants/constants.dart';
import '../services/analytics_event.dart';
import '../services/consent_service.dart';
import '../services/crash_service.dart';
import '../services/telemetry_service.dart';

/// First-run consent modal and post-auth consent sheet.
///
/// The full modal is still available for pre-auth fallback flows and the
/// post-auth "Customize" path. When deferred consent is enabled, Dashboard
/// shows the compact sheet after phone auth while all telemetry sinks remain
/// disabled until [ConsentState.hasDecided] is true.
///
/// POPIA stance:
///   * Crash reports default ON. Rationale: they contain technical metadata
///     only (no message bodies, no contact data), and the modal explicitly
///     surfaces the toggle so the user can opt out before dismissing.
///   * Product analytics defaults ON. Events are bucketed and PII-scrubbed
///     (see `analytics_event.dart`). The toggle is visible and pre-checked
///     -- the user can untick it before saving, or change it later via
///     Settings -> Privacy.
///   * Session replay defaults OFF. Replay is screen recording and sits
///     closer to POPIA s26 special PI; it stays opt-in. "Accept all" is the
///     one-tap path to enable it.
///   * The user cannot dismiss the modal without making a choice (no
///     barrier-tap to close, system back is intercepted by [PopScope]).
///   * "Reject all" is exposed as a top-right text link with equal
///     prominence to the save action — POPIA requires refusal to be at
///     least as easy as acceptance.
class ConsentModal extends StatefulWidget {
  const ConsentModal({super.key, this.surface = 'first_run_modal'});

  final String surface;

  /// Shows the full modal and returns once the user has made a choice.
  /// Safe to call multiple times — subsequent calls return immediately if
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

  static Future<void> showPostAuthIfNeeded(BuildContext context) async {
    if (ConsentService.instance.state.hasDecided) return;
    if (!context.mounted) return;
    final action = await showModalBottomSheet<_PostAuthConsentAction>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => const _PostAuthConsentSheet(),
    );
    if (!context.mounted || ConsentService.instance.state.hasDecided) return;
    if (action == _PostAuthConsentAction.customize) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const ConsentModal(surface: 'post_auth_customize'),
      );
    }
  }

  @override
  State<ConsentModal> createState() => _ConsentModalState();
}

enum _PostAuthConsentAction { customize }

Future<void> _recordConsentDecision({
  required bool analytics,
  required bool replay,
  required bool crash,
  required String surface,
}) async {
  await ConsentService.instance.recordDecision(
    analytics: analytics,
    replay: replay,
    crash: crash,
  );
  await CrashService.instance.applyConsent(ConsentService.instance.state);
  await TelemetryService.instance.applyConsent(ConsentService.instance.state);

  await TelemetryService.instance.capture(
    ConsentDecided(
      analytics: analytics,
      replay: replay,
      crash: crash,
      surface: surface,
    ),
  );
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
    _analytics = initial.analytics; // true  on first run (default-on)
    _replay = initial.replay; // false on first run (opt-in only)
    _crash = initial.crash; // true  on first run
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    await _recordConsentDecision(
      analytics: _analytics,
      replay: _replay,
      crash: _crash,
      surface: widget.surface,
    );

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _rejectAll() async {
    setState(() {
      _analytics = false;
      _replay = false;
      _crash = false;
    });
    await _save();
  }

  Future<void> _acceptAll() async {
    setState(() {
      _analytics = true;
      _replay = true;
      _crash = true;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    // POPIA: "Reject all" is given a first-class text link
                    // in the top-right so refusal is as easy as acceptance.
                    TextButton(
                      onPressed: _saving ? null : _rejectAll,
                      style: TextButton.styleFrom(
                        foregroundColor: kSecondaryAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Reject all'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: kPrimaryColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: kPrimaryColor,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Your privacy, your choice',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pick what Pasella can collect. You can change this '
                  'anytime in Settings → Privacy.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: kSecondaryAccent,
                  ),
                ),
                const SizedBox(height: 20),
                _ConsentOptionCard(
                  icon: Icons.bug_report_outlined,
                  title: 'Crash reports',
                  description:
                      'Help us fix bugs when something breaks. No personal '
                      'data is sent.',
                  value: _crash,
                  onChanged: _saving ? null : (v) => setState(() => _crash = v),
                ),
                const SizedBox(height: 10),
                _ConsentOptionCard(
                  icon: Icons.insights_outlined,
                  title: 'Usage insights',
                  description:
                      'Anonymous stats about which features get used. No '
                      'messages, no contacts.',
                  value: _analytics,
                  onChanged:
                      _saving
                          ? null
                          : (v) => setState(() {
                            _analytics = v;
                            if (!v) _replay = false;
                          }),
                ),
                const SizedBox(height: 10),
                _ConsentOptionCard(
                  icon: Icons.smart_display_outlined,
                  title: 'Screen replays',
                  description:
                      'Blurred recordings of your screens so we can debug '
                      'rough edges. Needs usage insights on.',
                  value: _replay && _analytics,
                  onChanged:
                      (_saving || !_analytics)
                          ? null
                          : (v) => setState(() => _replay = v),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save choices',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _saving ? null : _acceptAll,
                  style: TextButton.styleFrom(
                    foregroundColor: kPrimaryColor,
                    minimumSize: const Size(0, 40),
                  ),
                  child: const Text(
                    'Accept all',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PostAuthConsentSheet extends StatefulWidget {
  const _PostAuthConsentSheet();

  @override
  State<_PostAuthConsentSheet> createState() => _PostAuthConsentSheetState();
}

class _PostAuthConsentSheetState extends State<_PostAuthConsentSheet> {
  bool _saving = false;

  Future<void> _save({
    required bool analytics,
    required bool replay,
    required bool crash,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    await _recordConsentDecision(
      analytics: analytics,
      replay: replay,
      crash: crash,
      surface: 'post_auth_sheet',
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: kPrimaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Privacy choices',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Choose what Pasella can collect. You can change this anytime '
              'in Settings → Privacy.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: kSecondaryAccent,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed:
                  _saving
                      ? null
                      : () =>
                          _save(analytics: true, replay: false, crash: true),
              style: FilledButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Allow usage insights',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed:
                  _saving
                      ? null
                      : () =>
                          _save(analytics: false, replay: false, crash: true),
              style: OutlinedButton.styleFrom(
                foregroundColor: kSecondaryAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Essential only',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed:
                  _saving
                      ? null
                      : () => Navigator.of(
                        context,
                      ).pop(_PostAuthConsentAction.customize),
              child: const Text('Customize'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentOptionCard extends StatelessWidget {
  const _ConsentOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;

  /// Null when the option is disabled (saving, or analytics-gating for
  /// replay). The whole card visually dims when disabled.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: Material(
        color: kHighLightColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: disabled ? null : () => onChanged!(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: kPrimaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: kSecondaryAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  activeColor: kPrimaryColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
