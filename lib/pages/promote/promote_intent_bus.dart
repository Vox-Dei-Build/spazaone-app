/// Pending deep-link intent for the Promote area, e.g. from a push
/// notification tap. Set by the notification handler before navigation;
/// consumed once by [PromotionsPage] on first build.
///
/// We keep this lightweight (process-singleton, no persistence) because the
/// app process is alive whenever a notification is tapped — both for the
/// foreground path and for [FirebaseMessaging.getInitialMessage] taps that
/// cold-start the app.
library;

class PromoteIntent {
  /// 'promotions' or 'templates' — which tab to land on.
  final String tab;

  /// Optional: open a specific template's detail page.
  final String? templateId;

  /// Optional: trigger a follow-up action once the tab is loaded
  /// (e.g. 'run' to open the Run Promotion wizard).
  final String? action;

  const PromoteIntent({
    required this.tab,
    this.templateId,
    this.action,
  });

  factory PromoteIntent.fromUri(Uri uri) {
    final params = uri.queryParameters;
    return PromoteIntent(
      tab: params['tab'] ?? 'promotions',
      templateId: params['templateId'],
      action: params['action'],
    );
  }
}

class PromoteIntentBus {
  PromoteIntentBus._();
  static final PromoteIntentBus instance = PromoteIntentBus._();

  PromoteIntent? _pending;

  /// Stash a pending intent. Overwrites any previous value — the latest
  /// notification wins.
  void set(PromoteIntent intent) {
    _pending = intent;
  }

  /// Reads the pending intent and clears it. Returns `null` if none.
  PromoteIntent? consume() {
    final p = _pending;
    _pending = null;
    return p;
  }
}
