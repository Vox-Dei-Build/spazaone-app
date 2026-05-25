// Pure data model for the customer / global balance summary.
//
// Historical note: this class used to carry a `List<Widget>? children` slot
// that the `CustomerBalanceSummaryProvider` filled with `AddCreditPaymentButtons`
// so the summary card could render the CTAs underneath the numbers. That
// coupled the domain model to Flutter widgets and made the Pay Later layout
// impossible to evolve without touching the model. The CTAs are now rendered
// directly by the page (`PayLaterActionBar`), and this model holds numbers only.
class BalanceSummary {
  final double netBalance;
  final int paymentCount;
  final double paymentAmount;
  final int creditCount;
  final double creditAmount;
  final int? totalCustomers;
  final int? owingNumberOfCustomers;

  BalanceSummary({
    required this.netBalance,
    required this.paymentCount,
    required this.paymentAmount,
    required this.creditCount,
    required this.creditAmount,
    this.totalCustomers,
    this.owingNumberOfCustomers,
  });

  bool equals(BalanceSummary other) {
    return netBalance == other.netBalance &&
        paymentCount == other.paymentCount &&
        paymentAmount == other.paymentAmount &&
        creditCount == other.creditCount &&
        creditAmount == other.creditAmount &&
        totalCustomers == other.totalCustomers &&
        owingNumberOfCustomers == other.owingNumberOfCustomers;
  }
}
