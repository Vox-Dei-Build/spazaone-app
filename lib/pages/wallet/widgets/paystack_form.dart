import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/widgets/payment_response_screen.dart';
import 'package:pasella/services/paystack_service.dart';
import 'package:pasella/pages/wallet/widgets/paystack_webview.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';

class PaystackFormScreen extends StatefulWidget {
  const PaystackFormScreen({Key? key}) : super(key: key);

  @override
  _PaystackFormScreenState createState() => _PaystackFormScreenState();
}

class _PaystackFormScreenState extends State<PaystackFormScreen> {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool isLoading = false;

  /// Start Paystack transaction
  void _startTransaction() async {
    if (amountController.text.isEmpty || emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter email and amount")));
      return;
    }

    double amount = double.tryParse(amountController.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Enter a valid amount")));
      return;
    }

    setState(() => isLoading = true);

    String? checkoutUrl = await PaystackService.initializeTransaction(
        currentUserId, amount, emailController.text);

    setState(() => isLoading = false);

    if (checkoutUrl != null) {
      bool success = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaystackWebView(
            url: checkoutUrl,
            reference: "ref+$currentUserId",
            amount: amount,
          ),
        ),
      );

      if (success == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentResponseScreen(
              isSuccess: true,
              message: "Your balance has been successfully topped up!",
              amount: amount,
              reference: "ref+$currentUserId",
            ),
          ),
        );
      }
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentResponseScreen(
            isSuccess: false,
            message: "Transaction failed. Please try again.",
            amount: amount,
            reference: "ref+$currentUserId",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Top Up with Paystack'),
      body: Padding(
        padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomTextField(
              hintText: 'R100',
              prefixIcon: Icons.money_sharp,
              label: 'Enter Amount *',
              textInputType: TextInputType.number,
              maxLength: 20,
              controller: amountController,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'This field is required';
                }
                return null;
              },
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1.5),
            CustomTextField(
              hintText: 'user@example.com',
              prefixIcon: Icons.email_outlined,
              label: 'Enter Email *',
              textInputType: TextInputType.emailAddress,
              controller: emailController,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'This field is required';
                }
                return null;
              },
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Center(
                child: Stack(alignment: Alignment.center, children: [
              CustomButton(
                onTap: isLoading
                    ? () {}
                    : () async {
                        _startTransaction();
                      },
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 10.0),
                title: 'Proceed to Paystack',
              ),
              if (isLoading)
                const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
            ])),
          ],
        ),
      ),
    );
  }
}
