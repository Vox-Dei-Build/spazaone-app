import 'package:flutter/material.dart';
import 'package:pasella/pages/wallet/widgets/full_repayment_report.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/utils/wallet_utils.dart';

class SuspensionPaywall extends StatefulWidget {
  final WalletState walletState;

  const SuspensionPaywall({super.key, required this.walletState});

  @override
  State<SuspensionPaywall> createState() => _SuspensionPaywallState();
}

class _SuspensionPaywallState extends State<SuspensionPaywall> {
  // PAS-UX-12: collapse the paywall's four sibling FutureBuilders
  // into a single materialised breakdown. Cached in initState so a
  // rebuild (e.g. theme change) doesn't re-hit RemoteConfig.
  late final Future<WalletBreakdown> _breakdown =
      WalletUtils.computeBreakdown(widget.walletState);
  final WalletViewModel _walletVM = WalletViewModel();

  @override
  Widget build(BuildContext context) {
    final walletState = widget.walletState;

    return Scaffold(
      backgroundColor: Colors.red[50],
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(SizeConfig.heightMultiplier * 3),
          child: FutureBuilder<WalletBreakdown>(
            future: _breakdown,
            builder: (context, snapshot) {
              final b = snapshot.data ?? WalletBreakdown.loading;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 80, color: Colors.red),
                  SizedBox(height: SizeConfig.heightMultiplier * 4),
                  Text(
                    'Account Suspended',
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: SizeConfig.textMultiplier * 2.5,
                    ),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 3),
                  Text(
                    'Your account has been suspended due to missed repayments.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: SizeConfig.textMultiplier * 1.8,
                    ),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 7),
                  _infoTile('Fee Charged', b.advanceFee),
                  _infoTile('Amount Due', b.amountDue),
                  _infoTile('Bank Fee', b.bankFee),
                  _infoTile('Penalty Applied', b.penaltyFee),
                  const Divider(height: 32, thickness: 1),
                  _infoTile('Total Owed', b.totalOwed, isBold: true),
                  _infoTile('Suspended', b.suspended),
                  const Spacer(),
                  CustomButton(
                    title: 'Pay Back Now',
                    onTap: () =>
                        _walletVM.sendRepaymentWhatsAppMessage(context),
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
                            builder: (context) => FullRepaymentReportPage(
                                walletState: walletState),
                          ),
                        );
                      },
                      color: Colors.red,
                      icon: Icons.receipt_long,
                      fontSize: SizeConfig.textMultiplier * 2,
                    ),
                  ),
                ],
              );
            },
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
