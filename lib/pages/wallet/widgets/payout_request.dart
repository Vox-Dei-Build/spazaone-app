import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/utils/currency_util.dart';

class PayoutPage extends StatefulWidget {
  const PayoutPage({Key? key}) : super(key: key);

  @override
  _PayoutPageState createState() => _PayoutPageState();
}

class _PayoutPageState extends State<PayoutPage> {
  late WalletViewModel walletViewModel;

  @override
  void initState() {
    super.initState();
    walletViewModel = WalletViewModel();
  }

  @override
  void dispose() {
    walletViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(onBack: false, title: 'Request Payout'),
      body: Padding(
        padding: LayoutConstants.padding10Horizontal,
        child: StreamBuilder<WalletState>(
          stream: walletViewModel.walletStateStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final walletState = snapshot.data!;
            final double availableBalance = walletState.salesBalance;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Available Payout Balance',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(height: SizeConfig.heightMultiplier),
                Text(
                  CurrencyUtil.format(availableBalance),
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: Colors.green.shade700),
                ),
                if (availableBalance == 0) ...[
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  Text(
                    "⚠️ You have no available sales balance to withdraw.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: SizeConfig.textMultiplier * 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const Spacer(),
                ValueListenableBuilder<bool>(
                  valueListenable: walletViewModel.isProcessingPayoutRequest,
                  builder: (context, isProcessing, _) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomButton(
                          onTap: (availableBalance == 0 || isProcessing)
                              ? () {}
                              : () {
                                  walletViewModel.requestPayout(
                                      context, availableBalance);
                                },
                          title: 'Withdraw Full Amount',
                        ),
                        if (isProcessing)
                          const CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Something went wrong'),
        content: Text(
          message,
          style: const TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
