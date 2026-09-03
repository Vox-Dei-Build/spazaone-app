import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pasella/config/remote_config.dart';

/// Exact feature state used by production-isolated local device QA.
///
/// Every value is required as a compile-time define. This prevents a missing
/// Remote Config fetch from silently turning an emulator run into a different
/// product experience from the release being tested.
@immutable
class EmulatorQaFeatureProfile {
  const EmulatorQaFeatureProfile({
    required this.multiStoreOperators,
    required this.numberFirstOnboarding,
    required this.deferAuthConsent,
    required this.otpAutosubmit,
    required this.otpResendInDialog,
    required this.onlineSales,
    required this.campaignCreditPaystack,
    required this.ownedOrderPayments,
    required this.accountSettlementPayments,
    required this.customerPaymentRequests,
    required this.supplierOrderPayments,
    required this.merchantOnboardingIntro,
    required this.whatsAppCatalogStatus,
  });

  static const multiStoreKey = 'QA_FEATURE_MULTI_STORE_OPERATORS';
  static const numberFirstKey = 'QA_FEATURE_NUMBER_FIRST_ONBOARDING';
  static const deferConsentKey = 'QA_FEATURE_DEFER_AUTH_CONSENT';
  static const otpAutosubmitKey = 'QA_FEATURE_OTP_AUTOSUBMIT';
  static const otpResendKey = 'QA_FEATURE_OTP_RESEND_IN_DIALOG';
  static const onlineSalesKey = 'QA_FEATURE_ONLINE_SALES';
  static const campaignCreditPaystackKey =
      'QA_FEATURE_CAMPAIGN_CREDIT_PAYSTACK';
  static const ownedOrderPaymentsKey = 'QA_FEATURE_OWNED_ORDER_PAYMENTS';
  static const accountSettlementPaymentsKey =
      'QA_FEATURE_ACCOUNT_SETTLEMENT_PAYMENTS';
  static const customerPaymentRequestsKey =
      'QA_FEATURE_CUSTOMER_PAYMENT_REQUESTS';
  static const supplierOrderPaymentsKey = 'QA_FEATURE_SUPPLIER_ORDER_PAYMENTS';
  static const onboardingIntroKey = 'QA_FEATURE_MERCHANT_ONBOARDING_INTRO';
  static const whatsAppCatalogStatusKey = 'QA_FEATURE_WHATSAPP_CATALOG_STATUS';

  static const _multiStoreValue = String.fromEnvironment(multiStoreKey);
  static const _numberFirstValue = String.fromEnvironment(numberFirstKey);
  static const _deferConsentValue = String.fromEnvironment(deferConsentKey);
  static const _otpAutosubmitValue = String.fromEnvironment(otpAutosubmitKey);
  static const _otpResendValue = String.fromEnvironment(otpResendKey);
  static const _onlineSalesValue = String.fromEnvironment(onlineSalesKey);
  static const _campaignCreditPaystackValue =
      String.fromEnvironment(campaignCreditPaystackKey);
  static const _ownedOrderPaymentsValue =
      String.fromEnvironment(ownedOrderPaymentsKey);
  static const _accountSettlementPaymentsValue =
      String.fromEnvironment(accountSettlementPaymentsKey);
  static const _customerPaymentRequestsValue =
      String.fromEnvironment(customerPaymentRequestsKey);
  static const _supplierOrderPaymentsValue =
      String.fromEnvironment(supplierOrderPaymentsKey);
  static const _onboardingIntroValue =
      String.fromEnvironment(onboardingIntroKey);
  static const _whatsAppCatalogStatusValue =
      String.fromEnvironment(whatsAppCatalogStatusKey);

  final bool multiStoreOperators;
  final bool numberFirstOnboarding;
  final bool deferAuthConsent;
  final bool otpAutosubmit;
  final bool otpResendInDialog;
  final bool onlineSales;
  final bool campaignCreditPaystack;
  final bool ownedOrderPayments;
  final bool accountSettlementPayments;
  final bool customerPaymentRequests;
  final bool supplierOrderPayments;
  final bool merchantOnboardingIntro;
  final bool whatsAppCatalogStatus;

  factory EmulatorQaFeatureProfile.fromEnvironment() {
    return EmulatorQaFeatureProfile.fromValues(const {
      multiStoreKey: _multiStoreValue,
      numberFirstKey: _numberFirstValue,
      deferConsentKey: _deferConsentValue,
      otpAutosubmitKey: _otpAutosubmitValue,
      otpResendKey: _otpResendValue,
      onlineSalesKey: _onlineSalesValue,
      campaignCreditPaystackKey: _campaignCreditPaystackValue,
      ownedOrderPaymentsKey: _ownedOrderPaymentsValue,
      accountSettlementPaymentsKey: _accountSettlementPaymentsValue,
      customerPaymentRequestsKey: _customerPaymentRequestsValue,
      supplierOrderPaymentsKey: _supplierOrderPaymentsValue,
      onboardingIntroKey: _onboardingIntroValue,
      whatsAppCatalogStatusKey: _whatsAppCatalogStatusValue,
    });
  }

  @visibleForTesting
  factory EmulatorQaFeatureProfile.fromValues(Map<String, String> values) {
    bool requiredBool(String key) {
      final value = values[key]?.trim().toLowerCase() ?? '';
      if (value == 'true') return true;
      if (value == 'false') return false;
      throw StateError(
        'Emulator QA requires --dart-define=$key=true|false.',
      );
    }

    return EmulatorQaFeatureProfile(
      multiStoreOperators: requiredBool(multiStoreKey),
      numberFirstOnboarding: requiredBool(numberFirstKey),
      deferAuthConsent: requiredBool(deferConsentKey),
      otpAutosubmit: requiredBool(otpAutosubmitKey),
      otpResendInDialog: requiredBool(otpResendKey),
      onlineSales: requiredBool(onlineSalesKey),
      campaignCreditPaystack: requiredBool(campaignCreditPaystackKey),
      ownedOrderPayments: requiredBool(ownedOrderPaymentsKey),
      accountSettlementPayments: requiredBool(accountSettlementPaymentsKey),
      customerPaymentRequests: requiredBool(customerPaymentRequestsKey),
      supplierOrderPayments: requiredBool(supplierOrderPaymentsKey),
      merchantOnboardingIntro: requiredBool(onboardingIntroKey),
      whatsAppCatalogStatus: requiredBool(whatsAppCatalogStatusKey),
    );
  }
}

class FeatureFlags {
  static bool enableTopUp = true;
  static bool enableTransactionHistory = true;
  static bool enablePricingInfo = true;

  static bool enableBalancePayout = true;
  static bool enableCashAdvance = false;
  static bool enableBankingDetails = true;

  static bool enableAnonymousGate = false;
  // Campaign Credit checkout is remotely activatable in 4.8.0, but a missing
  // or failed Remote Config fetch must keep it dark.
  static bool enableTopUpPaystack = false;
  static bool enableMoveFunds = false;

  /// Presents the Online commerce hub. This does not enable any payment:
  /// each purpose also requires its client gate and server readiness.
  static bool enableOnlineSales = false;

  /// Independent client rollback gates beneath the Online hub presentation.
  /// Authoritative server readiness is still required for every initialization.
  static bool enableOwnedOrderPayments = false;
  static bool enableAccountSettlementPayments = false;
  static bool enableCustomerPaymentRequests = false;
  static bool enableSupplierOrderPayments = false;

  /// Multi-store/operator emergency rollback switch.
  ///
  /// Multi-store is a standard Spaza One feature, so missing or unavailable
  /// Remote Config must leave it enabled. Operations can still explicitly set
  /// the remote value to false to hide the surface during an incident.
  static bool enableMultiStoreOperators = true;
  static final ValueNotifier<bool> multiStoreOperatorsEnabled =
      ValueNotifier<bool>(true);
  static StreamSubscription<Set<String>>? _remoteConfigSubscription;

  /// Allows newly created stores to join the owner's campaign-credit wallet.
  ///
  /// This is an enrollment switch, not a destructive runtime kill switch:
  /// stores already enrolled continue using their canonical wallet even when
  /// this flag is later disabled, so funds can never appear to split.
  static bool enableSharedCampaignCreditsEnrollment = false;

  /// PAS-UX-22: number-first onboarding flow.
  ///
  /// When true, the app launches into `/phoneEntryPage` and routes new vs
  /// returning users server-side from a single phone field. The legacy
  /// `/loginPage` and `/registerPage` are kept registered for deep-link
  /// compatibility and redirect to `/phoneEntryPage` when this flag is on.
  /// Default false; flip via Remote Config key
  /// `FEATURE_NUMBER_FIRST_ONBOARDING_ENABLED`.
  static bool enableNumberFirstOnboarding = false;

  /// Defers the first-run telemetry consent prompt until after a merchant has
  /// completed phone authentication. Telemetry remains effectively disabled
  /// while consent is undecided.
  static bool enableDeferAuthConsent = false;

  /// Enables automatic OTP verification when the OS autofills or the user
  /// pastes/types a complete 6-digit code.
  static bool enableOtpAutosubmit = false;

  /// Keeps the user in the OTP dialog and exposes resend there instead of
  /// forcing "Cancel and try again".
  static bool enableOtpResendInDialog = false;

  /// Controls whether the concise merchant onboarding intro sheet is shown
  /// on the merchant's first Dashboard mount. Kept behind a flag
  /// so we can A/B or kill it remotely. The persistent
  /// [MerchantSetupCard] remains available from Settings → Shop Setup.
  ///
  /// Defaults to true so a missing / failed Remote Config fetch keeps
  /// the current behaviour.
  static bool enableMerchantOnboardingIntro = true;

  /// Merchant-facing catalogue status is a standard release feature. Remote
  /// Config remains an emergency presentation switch; server rollout is
  /// reported independently and remains authoritative.
  static bool enableWhatsAppCatalogStatus = true;
  static final ValueNotifier<bool> whatsAppCatalogStatusEnabled =
      ValueNotifier<bool>(true);

  static Future<void> loadFlags() async {
    final rc = await RemoteConfigService.getInstance();
    _applyFlags(rc);

    // The Remote Config SDK fetches real-time updates after app startup.
    // Re-apply the activated values so feature-gated UI updates immediately
    // instead of keeping the launch-time static value until the next process
    // restart.
    _remoteConfigSubscription ??= rc.activatedUpdates.listen((_) {
      _applyFlags(rc);
    });
  }

  @visibleForTesting
  static void applyFlagsForTesting(RemoteConfigBoolReader rc) {
    _applyFlags(rc);
  }

  static void applyEmulatorQaProfile(EmulatorQaFeatureProfile profile) {
    enableMultiStoreOperators = profile.multiStoreOperators;
    multiStoreOperatorsEnabled.value = profile.multiStoreOperators;
    enableNumberFirstOnboarding = profile.numberFirstOnboarding;
    enableDeferAuthConsent = profile.deferAuthConsent;
    enableOtpAutosubmit = profile.otpAutosubmit;
    enableOtpResendInDialog = profile.otpResendInDialog;
    enableOnlineSales = profile.onlineSales;
    enableTopUpPaystack = profile.campaignCreditPaystack;
    enableOwnedOrderPayments = profile.ownedOrderPayments;
    enableAccountSettlementPayments = profile.accountSettlementPayments;
    enableCustomerPaymentRequests = profile.customerPaymentRequests;
    enableSupplierOrderPayments = profile.supplierOrderPayments;
    enableMerchantOnboardingIntro = profile.merchantOnboardingIntro;
    enableWhatsAppCatalogStatus = profile.whatsAppCatalogStatus;
    whatsAppCatalogStatusEnabled.value = profile.whatsAppCatalogStatus;
  }

  static void _applyFlags(RemoteConfigBoolReader rc) {
    enableTopUp = rc.getBool('FEATURE_TOP_UP_ENABLED', defaultValue: true);
    enableTransactionHistory = rc.getBool(
      'FEATURE_TRANSACTION_HISTORY_ENABLED',
      defaultValue: true,
    );
    enablePricingInfo = rc.getBool(
      'FEATURE_PRICING_INFO_ENABLED',
      defaultValue: true,
    );

    enableBalancePayout = rc.getBool(
      'FEATURE_BALANCE_PAYOUT_ENABLED',
      defaultValue: true,
    );
    enableCashAdvance = rc.getBool(
      'FEATURE_CASH_ADVANCE_ENABLED',
      defaultValue: false,
    );
    enableBankingDetails = rc.getBool(
      'FEATURE_BANKING_DETAILS_ENABLED',
      defaultValue: true,
    );

    enableAnonymousGate = rc.getBool(
      'FEATURE_ANONYMOUS_GATE_ENABLED',
      defaultValue: false,
    );
    enableTopUpPaystack = rc.getBool(
      'FEATURE_TOP_UP_PAYSTACK_ENABLED',
      defaultValue: false,
    );
    enableMoveFunds = rc.getBool(
      'FEATURE_MOVE_FUNDS_ENABLED',
      defaultValue: false,
    );
    enableOnlineSales = rc.getBool(
      'FEATURE_ONLINE_SALES_ENABLED',
      defaultValue: false,
    );
    enableOwnedOrderPayments = rc.getBool(
      'FEATURE_OWNED_ORDER_PAYMENTS_ENABLED',
      defaultValue: false,
    );
    enableAccountSettlementPayments = rc.getBool(
      'FEATURE_ACCOUNT_SETTLEMENT_PAYMENTS_ENABLED',
      defaultValue: false,
    );
    enableCustomerPaymentRequests = rc.getBool(
      'FEATURE_CUSTOMER_PAYMENT_REQUESTS_ENABLED',
      defaultValue: false,
    );
    enableSupplierOrderPayments = rc.getBool(
      'FEATURE_SUPPLIER_ORDER_PAYMENTS_ENABLED',
      defaultValue: false,
    );
    enableMultiStoreOperators = rc.getBool(
      'FEATURE_MULTI_STORE_OPERATORS_ENABLED',
      defaultValue: true,
    );
    multiStoreOperatorsEnabled.value = enableMultiStoreOperators;
    enableSharedCampaignCreditsEnrollment = rc.getBool(
      'FEATURE_SHARED_CAMPAIGN_CREDITS_ENROLLMENT_ENABLED',
      defaultValue: false,
    );

    // PAS-UX-22: default false so a missing / failed Remote Config fetch
    // leaves us on the legacy two-screen flow.
    enableNumberFirstOnboarding = rc.getBool(
      'FEATURE_NUMBER_FIRST_ONBOARDING_ENABLED',
      defaultValue: false,
    );
    enableDeferAuthConsent = rc.getBool(
      'FEATURE_DEFER_AUTH_CONSENT_ENABLED',
      defaultValue: false,
    );
    enableOtpAutosubmit = rc.getBool(
      'FEATURE_OTP_AUTOSUBMIT_ENABLED',
      defaultValue: false,
    );
    enableOtpResendInDialog = rc.getBool(
      'FEATURE_OTP_RESEND_IN_DIALOG_ENABLED',
      defaultValue: false,
    );
    enableMerchantOnboardingIntro = rc.getBool(
      'FEATURE_MERCHANT_ONBOARDING_INTRO_ENABLED',
      defaultValue: true,
    );
    enableWhatsAppCatalogStatus = rc.getBool(
      'FEATURE_WHATSAPP_CATALOG_STATUS_ENABLED',
      defaultValue: true,
    );
    whatsAppCatalogStatusEnabled.value = enableWhatsAppCatalogStatus;
  }
}
