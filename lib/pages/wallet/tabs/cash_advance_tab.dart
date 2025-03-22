import 'package:flutter/material.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/widgets/full_repayment_report.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/utils/feature_flags.dart';

class CashAdvanceTab extends StatefulWidget {
  const CashAdvanceTab({super.key});

  @override
  State<CashAdvanceTab> createState() => _CashAdvanceTabState();
}

class _CashAdvanceTabState extends State<CashAdvanceTab> {
  final WalletViewModel walletVM = WalletViewModel();
  double maxAmount = 0.0; // Default value

  @override
  void initState() {
    super.initState();
    _fetchMaxAmount();
  }

  Future<void> _fetchMaxAmount() async {
    double fetchedAmount = await walletVM.getMaxCashAdvanceAmount();
    setState(() {
      maxAmount = fetchedAmount;
    });
  }

  /// Creates a styled row for cash advance terms
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

        return SingleChildScrollView(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: SizeConfig.heightMultiplier * 2),

                CustomButton(
                  title: 'Pay Back Now',
                  onTap: () => walletVM.sendRepaymentWhatsAppMessage(context),
                  color: Colors.green,
                  icon: Icons.payment,
                  fontSize: SizeConfig.textMultiplier * 2,
                  width: SizeConfig.imageSizeMultiplier * 60,
                ),

                SizedBox(height: SizeConfig.heightMultiplier * 2),

                CustomButton(
                  title: 'Get Cash Advance',
                  onTap: () =>
                      walletVM.requestCashAdvance(context, amount: 500.0),
                  color: Colors.blue,
                  icon: Icons.account_balance_wallet_sharp,
                  fontSize: SizeConfig.textMultiplier * 2,
                  width: SizeConfig.imageSizeMultiplier * 60,
                ),

                SizedBox(height: SizeConfig.heightMultiplier * 2), // Spacing

                CustomButton(
                  title: 'View Terms',
                  onTap: () => _showTermsSheet(context),
                  color: Colors.blue,
                  icon: Icons.receipt,
                  fontSize: SizeConfig.textMultiplier * 2,
                  width: SizeConfig.imageSizeMultiplier * 60,
                ),

                SizedBox(height: SizeConfig.heightMultiplier * 2), // Spacing

                CustomButton(
                  title: 'View Full Report',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            FullRepaymentReportPage(walletState: walletState),
                      ),
                    );
                  },
                  color: Colors.blue,
                  icon: Icons.receipt_long,
                  fontSize: SizeConfig.textMultiplier * 2,
                  width: SizeConfig.imageSizeMultiplier * 60,
                ),

                SizedBox(height: SizeConfig.heightMultiplier * 2), // Spacing

                if (FeatureFlags.enableMoveFunds) ...[
                  ElevatedButton(
                    onPressed: cashAdvanceBalance > 0
                        ? () => walletVM.transferToVirtualBalance(
                            context, cashAdvanceBalance)
                        : null, // 🔥 Disables button when balance is 0

                    style: ElevatedButton.styleFrom(
                      backgroundColor: cashAdvanceBalance > 0
                          ? Colors.blue // 🔹 Active State
                          : Colors.grey.shade400, // 🔹 Disabled State (Muted)

                      padding: EdgeInsets.symmetric(
                          vertical: SizeConfig.heightMultiplier * 1.5,
                          horizontal: SizeConfig.imageSizeMultiplier * 5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Move Funds to App',
                      style: TextStyle(
                        color: Colors.white, // 🔹 Muted text if disabled
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],

                SizedBox(
                    height: SizeConfig.heightMultiplier *
                        3), // Extra spacing at bottom
              ],
            ),
          ),
        );
      },
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
            mainAxisSize: MainAxisSize.min, // Adjusts size based on content
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

              // Close button
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
                        vertical: SizeConfig.heightMultiplier * 1.5),
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
}
