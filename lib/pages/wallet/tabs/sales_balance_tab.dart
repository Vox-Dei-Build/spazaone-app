import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/payout_request.dart';
import 'package:pasella/utils/feature_flags.dart';

class SalesBalanceTab extends StatefulWidget {
  const SalesBalanceTab({super.key});

  @override
  State<SalesBalanceTab> createState() => _SalesBalanceTabState();
}

class _SalesBalanceTabState extends State<SalesBalanceTab> {
  final WalletViewModel walletVM = WalletViewModel();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WalletState>(
      stream: walletVM.walletStateStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final walletState = snapshot.data!;
        final double salesBalance = walletState.salesBalance;
        final bool canWithdraw = salesBalance > 0 &&
            walletState.hasBankAccount &&
            !walletState.hasPendingPayout;
        const imageUrl = 'https://picsum.photos/id/13/2500/1667?blur';

        return SingleChildScrollView(
          padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCard(
                imageUrl: imageUrl,
                title: 'Withdraw',
                description: 'Withdraw your sales balance to your bank',
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
                        onPressed: salesBalance > 0
                            ? () => walletVM.transferToVirtualBalance(
                                context, salesBalance)
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
                              : walletState.salesBalance <= 0
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
    required String imageUrl,
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
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Image.network(
              imageUrl,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: SizeConfig.heightMultiplier),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.6,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 2),
                Row(
                  children: [
                    Expanded(child: primaryBtn),
                    SizedBox(width: SizeConfig.imageSizeMultiplier * 3),
                    Expanded(child: secondaryBtn),
                  ],
                ),
                if (footer != null) footer,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
