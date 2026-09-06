import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/dashboard/dashboard.dart';

void main() {
  group('merchant onboarding intro eligibility', () {
    test('a genuinely empty unseen store retains first-run onboarding', () {
      expect(
        shouldShowMerchantOnboardingIntroForStore(
          isOwner: true,
          introSeen: false,
          hasCustomers: false,
          hasProducts: false,
        ),
        isTrue,
      );
    });

    test('an existing customer suppresses first-customer onboarding', () {
      expect(
        shouldShowMerchantOnboardingIntroForStore(
          isOwner: true,
          introSeen: false,
          hasCustomers: true,
          hasProducts: false,
        ),
        isFalse,
      );
    });

    test('an existing product also identifies an established store', () {
      expect(
        shouldShowMerchantOnboardingIntroForStore(
          isOwner: true,
          introSeen: false,
          hasCustomers: false,
          hasProducts: true,
        ),
        isFalse,
      );
    });

    test('a previously dismissed intro stays dismissed for an empty store', () {
      expect(
        shouldShowMerchantOnboardingIntroForStore(
          isOwner: true,
          introSeen: true,
          hasCustomers: false,
          hasProducts: false,
        ),
        isFalse,
      );
    });

    test('an empty operator store never receives owner onboarding', () {
      expect(
          shouldShowMerchantOnboardingIntroForStore(
            isOwner: false,
            introSeen: false,
            hasCustomers: false,
            hasProducts: false,
          ),
          isFalse);
    });

    test('existing recorded sales also suppress first-use interruptions', () {
      expect(
          shouldShowMerchantOnboardingIntroForStore(
            isOwner: true,
            introSeen: false,
            hasCustomers: false,
            hasProducts: false,
            hasRecordedSales: true,
          ),
          isFalse);
    });
  });
}
