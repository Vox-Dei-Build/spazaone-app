import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/payout_request.dart';
import 'package:pasella/pages/wallet/tabs/cash_advance_tab.dart';
import 'package:pasella/utils/feature_flags.dart';

class SalesBalanceTab extends StatefulWidget {
  const SalesBalanceTab({super.key});

  @override
  State<SalesBalanceTab> createState() => _SalesBalanceTabState();
}

enum SalesView { sales, cashAdvance }

class _SalesBalanceTabState extends State<SalesBalanceTab> {
  final WalletViewModel walletVM = WalletViewModel();
  SalesView _selected = SalesView.sales;

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_selected == SalesView.cashAdvance) {
      content = const CashAdvanceTab();
    } else {
      content = StreamBuilder<WalletState>(
        stream: walletVM.walletStateStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final walletState = snapshot.data!;
          final double salesBalance = walletState.salesVirtualBalance;
          final bool canWithdraw = salesBalance > 0 &&
              walletState.hasBankAccount &&
              !walletState.hasPendingPayout;
          // PAS-UX-10: see cash_advance_tab — Lorem-Picsum hero image
          // replaced with branded colour band so the merchant
          // payments surface stops fingerprinting picsum.photos and
          // stops showing random stock photos as the visual for a
          // payout card.
          const heroColor = Color(0xff2B325F);

          return SingleChildScrollView(
            padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCard(
                  heroColor: heroColor,
                  heroIcon: Icons.account_balance_outlined,
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
                        style: TextStyle(
                            fontSize: SizeConfig.textMultiplier * 1.5)),
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
                                : walletState.salesVirtualBalance <= 0
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

    return Column(
      children: [
        if (FeatureFlags.enableCashAdvance)
          Theme(
            data: Theme.of(context).copyWith(
              segmentedButtonTheme: SegmentedButtonThemeData(
                style: ButtonStyle(
                  backgroundColor: MaterialStateProperty.resolveWith(
                    (states) => states.contains(MaterialState.selected)
                        ? Colors.green
                        : Colors.white,
                  ),
                  foregroundColor: MaterialStateProperty.resolveWith(
                    (states) => states.contains(MaterialState.selected)
                        ? Colors.white
                        : Colors.black87,
                  ),
                ),
              ),
            ),
            child: Padding(
              padding:
                  EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier),
              child: SegmentedButton<SalesView>(
                segments: const [
                  ButtonSegment(
                    value: SalesView.sales,
                    label: Text('Sales'),
                    icon: Icon(Icons.monetization_on),
                  ),
                  ButtonSegment(
                    value: SalesView.cashAdvance,
                    label: Text('Cash Advance'),
                    icon: Icon(Icons.account_balance),
                  ),
                ],
                selected: <SalesView>{_selected},
                onSelectionChanged: (selection) {
                  setState(() => _selected = selection.first);
                },
              ),
            ),
          ),
        Expanded(child: content),
      ],
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
