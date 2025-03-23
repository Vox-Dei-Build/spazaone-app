import 'package:pasella/config/remote_config.dart';

class FeatureFlags {
  static bool enableTopUp = true;
  static bool enableTransactionHistory = true;
  static bool enablePricingInfo = true;

  static bool enableBalancePayout = true;
  static bool enableCashAdvance = true;
  static bool enableBankingDetails = true;

  static bool enableAnonymousGate = false;
  static bool enableTopUpPaystack = false;
  static bool enableMoveFunds = false;

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
        rc.getBool('FEATURE_CASH_ADVANCE_ENABLED', defaultValue: true);
    enableBankingDetails =
        rc.getBool('FEATURE_BANKING_DETAILS_ENABLED', defaultValue: true);

    enableAnonymousGate =
        rc.getBool('FEATURE_ANONYMOUS_GATE_ENABLED', defaultValue: false);
    enableTopUpPaystack =
        rc.getBool('FEATURE_TOP_UP_PAYSTACK_ENABLED', defaultValue: false);
    enableMoveFunds =
        rc.getBool('FEATURE_MOVE_FUNDS_ENABLED', defaultValue: false);
  }
}
