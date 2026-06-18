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

  /// PAS-UX-22: number-first onboarding flow.
  ///
  /// When true, the app launches into `/phoneEntryPage` and routes new vs
  /// returning users server-side from a single phone field. The legacy
  /// `/loginPage` and `/registerPage` are kept registered for deep-link
  /// compatibility and redirect to `/phoneEntryPage` when this flag is on.
  /// Default false; flip via Remote Config key
  /// `FEATURE_NUMBER_FIRST_ONBOARDING_ENABLED`.
  static bool enableNumberFirstOnboarding = false;

  static Future<void> loadFlags() async {
    final rc = await RemoteConfigService.getInstance();

    enableTopUp = rc.getBool('FEATURE_TOP_UP_ENABLED', defaultValue: true);
    enableTransactionHistory =
        rc.getBool('FEATURE_TRANSACTION_HISTORY_ENABLED', defaultValue: true);
    enablePricingInfo =
        rc.getBool('FEATURE_PRICING_INFO_ENABLED', defaultValue: true);

    enableBalancePayout =
        rc.getBool('FEATURE_BALANCE_PAYOUT_ENABLED', defaultValue: true);
    enableCashAdvance =
        rc.getBool('FEATURE_CASH_ADVANCE_ENABLED', defaultValue: false);
    enableBankingDetails =
        rc.getBool('FEATURE_BANKING_DETAILS_ENABLED', defaultValue: true);

    enableAnonymousGate =
        rc.getBool('FEATURE_ANONYMOUS_GATE_ENABLED', defaultValue: false);
    enableTopUpPaystack =
        rc.getBool('FEATURE_TOP_UP_PAYSTACK_ENABLED', defaultValue: true);
    enableMoveFunds =
        rc.getBool('FEATURE_MOVE_FUNDS_ENABLED', defaultValue: false);

    // PAS-UX-22: default false so a missing / failed Remote Config fetch
    // leaves us on the legacy two-screen flow.
    enableNumberFirstOnboarding = rc.getBool(
      'FEATURE_NUMBER_FIRST_ONBOARDING_ENABLED',
      defaultValue: false,
    );
  }
}
