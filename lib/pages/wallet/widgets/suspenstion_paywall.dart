import 'package:flutter/material.dart';
import 'package:pasella/pages/wallet/widgets/full_repayment_report.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';

class SuspensionPaywall extends StatelessWidget {
  final WalletState walletState;

  const SuspensionPaywall({super.key, required this.walletState});

  @override
  Widget build(BuildContext context) {
    final totalDue =
        walletState.cashAdvanceWithdrawn * 1.1 + walletState.penaltyFee;
    final WalletViewModel walletVM = WalletViewModel();

    return Scaffold(
      backgroundColor: Colors.red[50],
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(SizeConfig.heightMultiplier * 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 80, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Account Suspended',
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.bold,
                  fontSize: SizeConfig.textMultiplier * 2.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your account has been suspended due to missed repayments.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: SizeConfig.textMultiplier * 1.8,
                ),
              ),
              const SizedBox(height: 30),
              _infoTile('Amount Due',
                  CurrencyUtil.format(walletState.cashAdvanceWithdrawn * 1.1)),
              _infoTile(
                  'Penalty Fee', CurrencyUtil.format(walletState.penaltyFee)),
              const Divider(height: 32, thickness: 1),
              _infoTile('Total Owed', CurrencyUtil.format(totalDue),
                  isBold: true),
              const Spacer(),
              CustomButton(
                title: 'Pay Back Now',
                onTap: () => walletVM.sendRepaymentWhatsAppMessage(context),
                color: Colors.green,
                icon: Icons.payment,
                fontSize: SizeConfig.textMultiplier * 2,
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 2),
              SizedBox(
                width: double.infinity,
                child: CustomButton(
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
                  color: Colors.red,
                  icon: Icons.receipt_long,
                  fontSize: SizeConfig.textMultiplier * 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoTile(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.8)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: SizeConfig.textMultiplier * 1.8,
              color: isBold ? Colors.red.shade900 : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
