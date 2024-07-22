import 'package:flutter/material.dart';
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
  double _availableBalance =
      0.0; // This will be passed or fetched from the previous page.

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
    _availableBalance = ModalRoute.of(context)!.settings.arguments as double;
    bool isProcessingPayoutRequest =
        walletViewModel.isProcessingPayoutRequest.value;

    return Scaffold(
      appBar: CustomAppBar(onBack: false, title: 'Request Payout'),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('Available Balance: ${CurrencyUtil.format(_availableBalance)}',
                style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 20),
            CustomTextField(
              controller: _amountController,
              hintText: 'Enter amount to withdraw',
              label: 'Amount',
              prefixIcon: Icons.money,
              textInputType: TextInputType.number,
            ),
            SizedBox(height: 20),
            Stack(
              alignment: Alignment.center,
              children: [
                CustomButton(
                  onTap: isProcessingPayoutRequest
                      ? () => null
                      : () {
                          // Implement the payout request logic
                          double requestAmount =
                              double.tryParse(_amountController.text) ?? 0;
                          if (requestAmount > 0 &&
                              requestAmount <= _availableBalance) {
                            // Proceed with the payout request
                            walletViewModel.requestPayout(
                                context, requestAmount);
                          } else {
                            // Show an error or feedback to the user
                            _showError(
                                "Please select a valid amount: value cannot be below 0 or greater than the available balance");
                          }
                        },
                  title: 'Request Payout',
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: walletViewModel.isProcessingPayoutRequest,
                  builder: (context, isProcessingPayoutRequest, child) {
                    return isProcessingPayoutRequest
                        ? CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white))
                        : SizedBox.shrink(); // Invisible when not processing
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    // Implement error handling
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Something went wrong'),
        content: Text(
          message,
          style: TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
}
