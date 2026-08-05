import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/main.dart';

void main() {
  test('notification prompt waits until every enabled first-run surface ends',
      () {
    expect(
      firstRunSurfacesCompleteForNotifications(
        consentDecided: true,
        rebrandNoticeSeen: true,
        onboardingIntroEnabled: true,
        onboardingIntroSeen: false,
      ),
      isFalse,
    );

    expect(
      firstRunSurfacesCompleteForNotifications(
        consentDecided: true,
        rebrandNoticeSeen: true,
        onboardingIntroEnabled: true,
        onboardingIntroSeen: true,
      ),
      isTrue,
    );
  });

  test('disabled onboarding intro cannot block notification setup', () {
    expect(
      firstRunSurfacesCompleteForNotifications(
        consentDecided: true,
        rebrandNoticeSeen: true,
        onboardingIntroEnabled: false,
        onboardingIntroSeen: false,
      ),
      isTrue,
    );
  });
}
