import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/payout_request.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';

class BalancePayoutTab extends StatelessWidget {
  const BalancePayoutTab({super.key});

  @override
  Widget build(BuildContext context) {
    final walletVM = WalletViewModel();

    return StreamBuilder<WalletState>(
      stream: walletVM.walletStateStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final walletState = snapshot.data!;
        bool canRequestPayout = walletState.cashAdvanceBalance > 0 &&
            walletState.hasBankAccount &&
            !walletState.hasPendingPayout; // ✅ Fixed variable name

        return Center(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomButton(
              title: 'Withdraw Cash Advance',
              onTap: () => {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PayoutPage(),
                  ),
                )
              },
              color: Colors.blue,
              icon: Icons.payments_outlined,
              fontSize: SizeConfig.textMultiplier * 2,
              width: SizeConfig.imageSizeMultiplier * 65,
              isDisabled: !canRequestPayout,
            ),
            if (!canRequestPayout)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  walletState.hasPendingPayout // ✅ Fixed variable name
                      ? 'Pending payout request.'
                      : walletState.cashAdvanceBalance <= 0
                          ? 'Insufficient balance.'
                          : 'Please add banking details first.',
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ));
      },
    );
  }
}
