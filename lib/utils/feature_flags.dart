import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pasella/config/remote_config.dart';

class FeatureFlags {
  static bool enableTopUp = true;
  static bool enableTransactionHistory = true;
  static bool enablePricingInfo = true;

  static bool enableBalancePayout = true;
  static bool enableCashAdvance = false;
  static bool enableBankingDetails = true;

  static bool enableAnonymousGate = false;
  static bool enableTopUpPaystack = true;
  static bool enableMoveFunds = false;

  /// Multi-store/operator release switch. Default false supports a controlled
  /// pilot and gives operations an immediate client-side rollback lever.
  static bool enableMultiStoreOperators = false;
  static final ValueNotifier<bool> multiStoreOperatorsEnabled =
      ValueNotifier<bool>(false);
  static const bool _forceMultiStoreForEmulator = bool.fromEnvironment(
    'ENABLE_MULTI_STORE_OPERATORS',
    defaultValue: false,
  );
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

  /// Controls whether the two-slide merchant onboarding intro sheet is
  /// shown on the merchant's first Dashboard mount. Kept behind a flag
  /// so we can A/B or kill it remotely as the persistent
  /// [MerchantSetupCard] on the Customers tab matures — the two
  /// surfaces overlap by design and we may not need both.
  ///
  /// Defaults to true so a missing / failed Remote Config fetch keeps
  /// the current behaviour.
  static bool enableMerchantOnboardingIntro = true;

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
      defaultValue: true,
    );
    enableMoveFunds = rc.getBool(
      'FEATURE_MOVE_FUNDS_ENABLED',
      defaultValue: false,
    );
    enableMultiStoreOperators = _forceMultiStoreForEmulator ||
        rc.getBool(
          'FEATURE_MULTI_STORE_OPERATORS_ENABLED',
          defaultValue: false,
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
  }
}
