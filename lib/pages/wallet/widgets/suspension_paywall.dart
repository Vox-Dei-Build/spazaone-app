import 'package:flutter/material.dart';
import 'package:pasella/pages/wallet/widgets/full_repayment_report.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/design/spaza_tokens.dart';
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<WalletBreakdown>(
            future: _breakdown,
            builder: (context, snapshot) {
              final b = snapshot.data ?? WalletBreakdown.loading;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 48, color: SpazaColors.error),
                  const SizedBox(height: 20),
                  const Text(
                    'Account Suspended',
                    style: TextStyle(
                      color: SpazaColors.error,
                      fontWeight: FontWeight.bold,
                      fontSize: 27,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Your account has been suspended due to missed repayments.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SpazaColors.muted,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _infoTile('Fee Charged', b.advanceFee),
                  _infoTile('Amount Due', b.amountDue),
                  _infoTile('Bank Fee', b.bankFee),
                  _infoTile('Penalty Applied', b.penaltyFee),
                  const Divider(height: 32, thickness: 1),
                  _infoTile('Total Owed', b.totalOwed, isBold: true),
                  _infoTile('Suspended', b.suspended),
                  const SizedBox(height: 24),
                  CustomButton(
                    title: 'Pay Back Now',
                    onTap: () =>
                        _walletVM.sendRepaymentWhatsAppMessage(context),
                    color: SpazaColors.action,
                    icon: Icons.payment,
                    fontSize: 14,
                  ),
                  const SizedBox(height: 16),
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
                      color: SpazaColors.heading,
                      icon: Icons.receipt_long,
                      fontSize: 14,
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
              color: isBold ? SpazaColors.error : SpazaColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
