import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/utils/feature_flags.dart';

class _FakeRemoteConfig implements RemoteConfigBoolReader {
  _FakeRemoteConfig(this.values);

  final Map<String, bool> values;

  @override
  bool getBool(String key, {bool defaultValue = false}) {
    return values[key] ?? defaultValue;
  }
}

void main() {
  tearDown(() {
    FeatureFlags.applyFlagsForTesting(_FakeRemoteConfig(const {}));
  });

  test('multi-store stays enabled when Remote Config is unavailable', () {
    FeatureFlags.applyFlagsForTesting(_FakeRemoteConfig(const {}));

    expect(FeatureFlags.enableMultiStoreOperators, isTrue);
    expect(FeatureFlags.multiStoreOperatorsEnabled.value, isTrue);
  });

  test('multi-store notifier follows activated feature flag values', () {
    final reader = _FakeRemoteConfig({
      'FEATURE_MULTI_STORE_OPERATORS_ENABLED': true,
    });

    FeatureFlags.applyFlagsForTesting(reader);

    expect(FeatureFlags.enableMultiStoreOperators, isTrue);
    expect(FeatureFlags.multiStoreOperatorsEnabled.value, isTrue);

    reader.values['FEATURE_MULTI_STORE_OPERATORS_ENABLED'] = false;
    FeatureFlags.applyFlagsForTesting(reader);

    expect(FeatureFlags.enableMultiStoreOperators, isFalse);
    expect(FeatureFlags.multiStoreOperatorsEnabled.value, isFalse);
  });

  test('online sales stay hidden until the provider flag is enabled', () {
    FeatureFlags.applyFlagsForTesting(_FakeRemoteConfig(const {}));
    expect(FeatureFlags.enableOnlineSales, isFalse);

    FeatureFlags.applyFlagsForTesting(
      _FakeRemoteConfig({'FEATURE_ONLINE_SALES_ENABLED': true}),
    );
    expect(FeatureFlags.enableOnlineSales, isTrue);
  });

  test('Campaign Credit Paystack stays dark by default and follows its flag',
      () {
    FeatureFlags.applyFlagsForTesting(_FakeRemoteConfig(const {}));
    expect(FeatureFlags.enableTopUpPaystack, isFalse);

    FeatureFlags.applyFlagsForTesting(
      _FakeRemoteConfig({'FEATURE_TOP_UP_PAYSTACK_ENABLED': true}),
    );

    expect(FeatureFlags.enableTopUpPaystack, isTrue);
  });

  test('commerce payment capabilities fail closed and switch independently',
      () {
    FeatureFlags.applyFlagsForTesting(_FakeRemoteConfig(const {}));
    expect(FeatureFlags.enableOwnedOrderPayments, isFalse);
    expect(FeatureFlags.enableAccountSettlementPayments, isFalse);
    expect(FeatureFlags.enableSupplierOrderPayments, isFalse);

    FeatureFlags.applyFlagsForTesting(
      _FakeRemoteConfig({
        'FEATURE_OWNED_ORDER_PAYMENTS_ENABLED': true,
        'FEATURE_ACCOUNT_SETTLEMENT_PAYMENTS_ENABLED': false,
        'FEATURE_SUPPLIER_ORDER_PAYMENTS_ENABLED': true,
      }),
    );
    expect(FeatureFlags.enableOwnedOrderPayments, isTrue);
    expect(FeatureFlags.enableAccountSettlementPayments, isFalse);
    expect(FeatureFlags.enableSupplierOrderPayments, isTrue);
  });

  test('emulator QA profile applies every release-relevant value together', () {
    final profile = EmulatorQaFeatureProfile.fromValues(const {
      EmulatorQaFeatureProfile.multiStoreKey: 'true',
      EmulatorQaFeatureProfile.numberFirstKey: 'false',
      EmulatorQaFeatureProfile.deferConsentKey: 'false',
      EmulatorQaFeatureProfile.otpAutosubmitKey: 'false',
      EmulatorQaFeatureProfile.otpResendKey: 'false',
      EmulatorQaFeatureProfile.onlineSalesKey: 'false',
      EmulatorQaFeatureProfile.campaignCreditPaystackKey: 'true',
      EmulatorQaFeatureProfile.ownedOrderPaymentsKey: 'true',
      EmulatorQaFeatureProfile.accountSettlementPaymentsKey: 'false',
      EmulatorQaFeatureProfile.supplierOrderPaymentsKey: 'true',
      EmulatorQaFeatureProfile.onboardingIntroKey: 'true',
    });

    FeatureFlags.applyEmulatorQaProfile(profile);

    expect(FeatureFlags.enableMultiStoreOperators, isTrue);
    expect(FeatureFlags.multiStoreOperatorsEnabled.value, isTrue);
    expect(FeatureFlags.enableNumberFirstOnboarding, isFalse);
    expect(FeatureFlags.enableDeferAuthConsent, isFalse);
    expect(FeatureFlags.enableOtpAutosubmit, isFalse);
    expect(FeatureFlags.enableOtpResendInDialog, isFalse);
    expect(FeatureFlags.enableOnlineSales, isFalse);
    expect(FeatureFlags.enableTopUpPaystack, isTrue);
    expect(FeatureFlags.enableOwnedOrderPayments, isTrue);
    expect(FeatureFlags.enableAccountSettlementPayments, isFalse);
    expect(FeatureFlags.enableSupplierOrderPayments, isTrue);
    expect(FeatureFlags.enableMerchantOnboardingIntro, isTrue);
  });

  test('emulator QA profile refuses missing or ambiguous values', () {
    expect(
      () => EmulatorQaFeatureProfile.fromValues(const {}),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(EmulatorQaFeatureProfile.multiStoreKey),
        ),
      ),
    );

    expect(
      () => EmulatorQaFeatureProfile.fromValues(const {
        EmulatorQaFeatureProfile.multiStoreKey: 'yes',
      }),
      throwsStateError,
    );
  });
}
