import 'package:intl/intl.dart';
import 'package:pasella/config/fees_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/utils/currency_util.dart';

/// PAS-UX-12: pre-computed wallet breakdown.
///
/// Audit found three surfaces (the wallet repayment bottom sheet,
/// the full repayment report page, and the suspension paywall) each
/// rendering between three and five `FutureBuilder<String>` siblings
/// against [WalletUtils]. Each future independently called
/// `RemoteConfigService.getInstance().getDouble(...)` for fee
/// percentages that never change mid-screen, producing a cascade of
/// "..." placeholders that resolved at different frames.
///
/// [WalletBreakdown] is the materialised result. Compute it once via
/// [WalletUtils.computeBreakdown], then bind every row to a single
/// snapshot so the screen renders in one frame.
class WalletBreakdown {
  final String advanceFee;
  final String bankFee;
  final String penaltyFee;
  final String amountDue;
  final String totalOwed;
  final String dueDate;
  final String suspended;

  const WalletBreakdown({
    required this.advanceFee,
    required this.bankFee,
    required this.penaltyFee,
    required this.amountDue,
    required this.totalOwed,
    required this.dueDate,
    required this.suspended,
  });

  /// Placeholder shown while the underlying futures are still in
  /// flight. Mirrors the legacy '...' text the per-row builders
  /// fell back to so the visual cadence is unchanged.
  static const WalletBreakdown loading = WalletBreakdown(
    advanceFee: '...',
    bankFee: '...',
    penaltyFee: '...',
    amountDue: '...',
    totalOwed: '...',
    dueDate: '...',
    suspended: '...',
  );
}

class WalletUtils {
  /// PAS-UX-12: compute every fee/repayment row in a single async
  /// pass.
  ///
  /// Reads the multiplier and bank-fee percentage exactly once and
  /// runs the three independent remote-config-backed futures in
  /// parallel via [Future.wait]. Result is a [WalletBreakdown] that
  /// callers bind to a single [FutureBuilder].
  static Future<WalletBreakdown> computeBreakdown(
      WalletState walletState) async {
    final results = await Future.wait([
      FeesConfig.getCashAdvanceMultiplier(),
      FeesConfig.getAdvanceFee(),
      FeesConfig.getBankFee(),
    ]);
    final multiplier = results[0];
    final advancePct = results[1];
    final bankPct = results[2];

    final amountDueValue = walletState.cashAdvanceWithdrawn * multiplier;
    final advanceFeeValue =
        (walletState.cashAdvanceWithdrawn * advancePct) / 100;
    final bankFeeValue = (walletState.cashAdvanceWithdrawn * bankPct) / 100;
    final totalOwedValue =
        amountDueValue + walletState.penaltyFee + bankFeeValue;

    return WalletBreakdown(
      advanceFee: CurrencyUtil.format(advanceFeeValue),
      bankFee: CurrencyUtil.format(bankFeeValue),
      penaltyFee: formatPenaltyFee(walletState),
      amountDue: CurrencyUtil.format(amountDueValue),
      totalOwed: CurrencyUtil.format(totalOwedValue),
      dueDate: formatDueDate(walletState),
      suspended: formatSuspendedStatus(walletState),
    );
  }

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

  Future<String> getMaxCashAdvanceAmount() async {
    final double maxAmount = await FeesConfig.getMaxCashAdvanceAmount();

    return CurrencyUtil.format(maxAmount);
  }
}
