import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/utils/currency_util.dart';

class PayoutPage extends StatefulWidget {
  const PayoutPage({Key? key}) : super(key: key);

  @override
  _PayoutPageState createState() => _PayoutPageState();
}

class _PayoutPageState extends State<PayoutPage> {
  late WalletViewModel walletViewModel;
  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    walletViewModel = WalletViewModel();
  }

  @override
  void dispose() {
    _amountController.dispose();
    walletViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(onBack: false, title: 'Request Payout'),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<WalletState>(
          stream: walletViewModel.walletStateStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final walletState = snapshot.data!;
            final double availableBalance = walletState.cashAdvanceBalance;
            bool isProcessingPayoutRequest =
                walletViewModel.isProcessingPayoutRequest.value;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Available Balance: ${CurrencyUtil.format(availableBalance)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (availableBalance == 0) ...[
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  Text(
                    "⚠️ You have no available balance to withdraw. You first need to qualify for a cashadvance.",
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: SizeConfig.textMultiplier * 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                SizedBox(height: SizeConfig.heightMultiplier * 2),
                CustomTextField(
                  controller: _amountController,
                  hintText: 'Enter amount to withdraw',
                  label: 'Amount',
                  prefixIcon: Icons.money,
                  textInputType: TextInputType.number,
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 2),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomButton(
                      onTap: isProcessingPayoutRequest
                          ? () {}
                          : () {
                              double requestAmount =
                                  double.tryParse(_amountController.text) ?? 0;
                              if (requestAmount > 0 &&
                                  requestAmount <= availableBalance) {
                                walletViewModel.requestPayout(
                                    context, requestAmount);
                              } else {
                                _showError(
                                    "Please select a valid amount: value cannot be below 0 or greater than the available balance");
                              }
                            },
                      title: 'Request Payout',
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable:
                          walletViewModel.isProcessingPayoutRequest,
                      builder: (context, isProcessingPayoutRequest, child) {
                        return isProcessingPayoutRequest
                            ? const CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white))
                            : const SizedBox.shrink();
                      },
                    ),
                  ],
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
