import 'package:intl/intl.dart';
import 'package:pasella/config/fees_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/utils/currency_util.dart';

class WalletUtils {
  /// Calculate total repayment amount with multiplier
  static Future<String> calculateAmountDue(WalletState walletState) async {
    final multiplier = await FeesConfig.getCashAdvanceMultiplier();

    final repaymentDue = walletState.cashAdvanceWithdrawn * multiplier;
    return CurrencyUtil.format(repaymentDue);
  }

  /// Return penalty fee as formatted string
  static String formatPenaltyFee(WalletState walletState) {
    if (walletState.penaltyFee > 0) {
      return CurrencyUtil.format(walletState.penaltyFee);
    } else {
      return 'No penalty';
    }
  }

  static Future<String> calculateAdvanceFee(WalletState walletState) async {
    final advanceFee = await FeesConfig.getAdvanceFee();
    final fee = (walletState.cashAdvanceWithdrawn * advanceFee) / 100;
    return CurrencyUtil.format(fee);
  }

  /// Calculate Bank Fee based on percentage and withdrawn amount
  static Future<String> calculateBankFee(WalletState walletState) async {
    final bankFeePercentage = await FeesConfig.getBankFee();
    final fee = (walletState.cashAdvanceWithdrawn * bankFeePercentage) / 100;
    return CurrencyUtil.format(fee);
  }

  /// Return formatted due date or fallback
  static String formatDueDate(WalletState walletState) {
    if (walletState.cashAdvanceDueDate != null) {
      return DateFormat('dd MMM yyyy').format(walletState.cashAdvanceDueDate!);
    } else {
      return 'Not Set';
    }
  }

  /// Return Yes/No for suspension
  static String formatSuspendedStatus(WalletState walletState) {
    return walletState.accountSuspended ? 'Yes' : 'No';
  }

  /// Total owed = amount due (with multiplier) + penalty + bank fee
  static Future<String> calculateTotalOwedWithPenaltyAndBankFee(
      WalletState walletState) async {
    final multiplier = await FeesConfig.getCashAdvanceMultiplier();
    final bankFeePercentage = await FeesConfig.getBankFee();

    final amountDue = walletState.cashAdvanceWithdrawn * multiplier;
    final bankFee =
        (walletState.cashAdvanceWithdrawn * bankFeePercentage) / 100;
    final total = amountDue + walletState.penaltyFee + bankFee;

    return CurrencyUtil.format(total);
  }
}
