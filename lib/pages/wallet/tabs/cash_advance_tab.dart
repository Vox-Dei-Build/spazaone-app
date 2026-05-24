import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/full_repayment_report.dart';
import 'package:pasella/pages/wallet/widgets/payout_request.dart';
import 'package:pasella/utils/feature_flags.dart';

class CashAdvanceTab extends StatefulWidget {
  const CashAdvanceTab({super.key});

  @override
  State<CashAdvanceTab> createState() => _CashAdvanceTabState();
}

class _CashAdvanceTabState extends State<CashAdvanceTab> {
  final WalletViewModel walletVM = WalletViewModel();
  double maxAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchMaxAmount();
  }

  Future<void> _fetchMaxAmount() async {
    double fetchedAmount = await walletVM.getMaxCashAdvanceAmount();
    if (!mounted) return;
    setState(() {
      maxAmount = fetchedAmount;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WalletState>(
      stream: walletVM.walletStateStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final walletState = snapshot.data!;
        final double cashAdvanceBalance = walletState.cashAdvanceBalance;
        final bool canWithdraw = cashAdvanceBalance > 0 &&
            walletState.hasBankAccount &&
            !walletState.hasPendingPayout;
        // PAS-UX-10: previously these cards loaded blurred Lorem
        // Picsum stock photos as hero images on a live merchant
        // payments surface. Picsum is a placeholder service —
        // shipping it in production looks unfinished, fingerprints
        // a third-party domain on every render, and (because the
        // images are random per id) sometimes loaded an irrelevant
        // photo as the visual for "Get cash advance instantly".
        // Replaced with branded colour bands keyed off the card's
        // intent. Real, on-message illustrations can land later as
        // local assets without changing the card layout.
        const advanceColor = Color(0xff1c863b); // brand green
        const eligibilityColor = Color(0xff4d4d4d);
        const historyColor = Color(0xff2B325F);

        return SingleChildScrollView(
          padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              /// Request Advance Card
              _buildCard(
                heroColor: advanceColor,
                heroIcon: Icons.payments_outlined,
                title: 'Get cash advance instantly',
                description:
                    'Need extra cash? Request a cash advance based on your transaction history.',
                primaryBtn: FilledButton.icon(
                  onPressed: () => walletVM.requestCashAdvance(
                    context,
                    amount: 500.0,
                  ),
                  icon: Icon(Icons.account_balance_wallet,
                      size: SizeConfig.textMultiplier * 1.5),
                  label: Text("Request",
                      style:
                          TextStyle(fontSize: SizeConfig.textMultiplier * 1.5)),
                ),
                secondaryBtn: OutlinedButton.icon(
                  onPressed: () => _showTermsSheet(context),
                  icon: Icon(Icons.info_outline,
                      size: SizeConfig.textMultiplier * 1.5),
                  label: Text("View terms",
                      style:
                          TextStyle(fontSize: SizeConfig.textMultiplier * 1.5)),
                ),
              ),

              /// Repayment Card
              _buildCard(
                heroColor: eligibilityColor,
                heroIcon: Icons.account_balance_wallet_outlined,
                title: 'Repay what you owe',
                description:
                    'Settle your cash advance now and view your full repayment history.',
                primaryBtn: FilledButton.icon(
                  onPressed: () =>
                      walletVM.sendRepaymentWhatsAppMessage(context),
                  icon: Icon(Icons.payment,
                      size: SizeConfig.textMultiplier * 1.5),
                  label: Text("Repay now",
                      style:
                          TextStyle(fontSize: SizeConfig.textMultiplier * 1.5)),
                ),
                secondaryBtn: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullRepaymentReportPage(
                          walletState: walletState,
                        ),
                      ),
                    );
                  },
                  icon: Icon(Icons.receipt_long,
                      size: SizeConfig.textMultiplier * 1.5),
                  label: Text("View report",
                      style:
                          TextStyle(fontSize: SizeConfig.textMultiplier * 1.5)),
                ),
              ),

              /// Withdraw / Move Funds Card
              _buildCard(
                heroColor: historyColor,
                heroIcon: Icons.account_balance_outlined,
                title: 'Withdraw',
                description: 'Withdraw your balance to your bank',
                primaryBtn: FilledButton.icon(
                  onPressed: canWithdraw
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PayoutPage(),
                            ),
                          );
                        }
                      : null,
                  icon: Icon(Icons.payments_outlined,
                      size: SizeConfig.textMultiplier * 1.5),
                  label: Text("Withdraw",
                      style:
                          TextStyle(fontSize: SizeConfig.textMultiplier * 1.5)),
                ),
                secondaryBtn: FeatureFlags.enableMoveFunds
                    ? OutlinedButton.icon(
                        onPressed: cashAdvanceBalance > 0
                            ? () => walletVM.transferToVirtualBalance(
                                context, cashAdvanceBalance)
                            : null,
                        icon: Icon(Icons.swap_horiz,
                            size: SizeConfig.textMultiplier * 1.5),
                        label: Text("Move funds",
                            style: TextStyle(
                                fontSize: SizeConfig.textMultiplier * 1.5)),
                      )
                    : const SizedBox.shrink(),
                footer: !canWithdraw
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          walletState.hasPendingPayout
                              ? 'Pending payout request.'
                              : walletState.cashAdvanceBalance <= 0
                                  ? 'Insufficient balance.'
                                  : 'Please add banking details first.',
                          style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: SizeConfig.textMultiplier * 1.5),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard({
    required Color heroColor,
    required IconData heroIcon,
    required String title,
    required String description,
    required Widget primaryBtn,
    required Widget secondaryBtn,
    Widget? footer,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      margin: EdgeInsets.only(bottom: SizeConfig.heightMultiplier * 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // PAS-UX-10: branded hero band replaces the previous
          // Lorem-Picsum stock-photo network image. Solid colour +
          // intent-matched icon keeps the card silhouette while
          // removing third-party network dependency on every render.
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              height: 120,
              width: double.infinity,
              color: heroColor,
              child: Icon(
                heroIcon,
                size: 56,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ),

          // Card Content
          Padding(
            padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Headline
                Text(
                  title,
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: SizeConfig.heightMultiplier),

                // Supporting text
                Text(
                  description,
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.6,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 2),

                // Buttons side-by-side
                Row(
                  children: [
                    Expanded(child: secondaryBtn),
                    SizedBox(width: SizeConfig.imageSizeMultiplier * 3),
                    Expanded(child: primaryBtn),
                  ],
                ),

                if (footer != null) ...[
                  SizedBox(height: SizeConfig.heightMultiplier * 1.5),
                  footer,
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showTermsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  "💡 Cash Advance Terms",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: SizeConfig.textMultiplier * 2.2,
                    color: Colors.black,
                  ),
                ),
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 1.5),
              _termsRow("Repayment Period", "1 Week"),
              _termsRow("Fee", "10% of borrowed amount"),
              _termsRow("Example", "R1000 → Repay R1100"),
              _termsRow("Max Amount (for now)", "R$maxAmount"),
              _termsRow("Approval Basis", "Historical transactions"),
              _termsRow("Balance Update", "After approval"),
              _termsRow("Payout", "Linked account"),
              SizedBox(height: SizeConfig.heightMultiplier * 2),
              Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: SizeConfig.imageSizeMultiplier * 5,
                      vertical: SizeConfig.heightMultiplier * 1.5,
                    ),
                    child: const Text("Close",
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _termsRow(String title, String value) {
    return Padding(
      padding:
          EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 0.2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.6),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.6,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
