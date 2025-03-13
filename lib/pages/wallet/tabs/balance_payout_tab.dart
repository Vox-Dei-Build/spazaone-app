import 'package:flutter/material.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';

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
        bool canRequestPayout = walletState.balance > 0 &&
            walletState.hasBankAccount &&
            !walletState.hasPendingPayout; // ✅ Fixed variable name

        return Center(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: canRequestPayout
                  ? () {
                      // handle payout request
                    }
                  : null,
              child: const Text('Request Payout'),
            ),
            if (!canRequestPayout)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  walletState.hasPendingPayout // ✅ Fixed variable name
                      ? 'Pending payout request.'
                      : walletState.balance <= 0
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
