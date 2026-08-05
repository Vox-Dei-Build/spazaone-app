import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/dashboard/dashboard.dart';
import 'package:pasella/services/consent_service.dart';

void main() {
  test('dashboard stays behind a neutral gate until privacy is decided', () {
    expect(
      shouldHoldDashboardForConsent(
        consent: const ConsentState.firstRun(),
        consentSurfaceCompleted: false,
      ),
      isTrue,
    );

    final decided = ConsentState(
      analytics: false,
      replay: false,
      crash: true,
      decidedAt: DateTime(2026, 8, 5),
    );

    // Persisting the decision happens before the bottom sheet pops. Keep the
    // underlying onboarding UI hidden during that short intermediate state.
    expect(
      shouldHoldDashboardForConsent(
        consent: decided,
        consentSurfaceCompleted: false,
      ),
      isTrue,
    );

    expect(
      shouldHoldDashboardForConsent(
        consent: decided,
        consentSurfaceCompleted: true,
      ),
      isFalse,
    );
  });
}
