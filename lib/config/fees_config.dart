import 'package:pasella/config/remote_config.dart';

class FeesConfig {
  static Future<double> getBankFee() async =>
      (await RemoteConfigService.getInstance())
          .getDouble('BANK_FEE_PERCENTAGE');

  static Future<double> getAdvanceFee() async =>
      (await RemoteConfigService.getInstance())
          .getDouble('ADVANCE_FEE_PERCENTAGE');

  static Future<double> getPenaltyFee() async =>
      (await RemoteConfigService.getInstance())
          .getDouble('PENALTY_FEE_PERCENTAGE');

  static Future<double> getTopUpFee() async =>
      (await RemoteConfigService.getInstance())
          .getDouble('TOP_UP_FEE_PERCENTAGE');

  static Future<double> getCashAdvanceMultiplier() async =>
      (await RemoteConfigService.getInstance())
          .getDouble('CASH_ADVANCE_REPAYMENT_MULTIPLIER');
}
