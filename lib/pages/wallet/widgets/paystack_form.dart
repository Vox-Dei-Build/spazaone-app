import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/widgets/payment_response_screen.dart';
import 'package:pasella/services/paystack_service.dart'; // uses initializeTopUp(...)
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

  /// Start Paystack TOP-UP transaction (purpose = 'topup')
  Future<void> _startTransaction() async {
    final messenger = ScaffoldMessenger.of(context);

    if (amountController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Please enter email and amount")),
      );
      return;
    }

    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Enter a valid amount")),
      );
      return;
    }

    if (currentUserId.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text("You must be signed in")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      // 🔑 This calls the initializer with purpose: 'topup' and minor units handled inside the service.
      final init = await PaystackService.initializeTopUp(
        userId: currentUserId,
        amount: amount, // rands
        email: emailController.text.trim(),
      );

      setState(() => isLoading = false);

      if (init == null) {
        // Failed to create link
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentResponseScreen(
              isSuccess: false,
              message: "Transaction failed. Please try again.",
              amount: amount,
              reference: "—",
            ),
          ),
        );
        return;
      }

      // Open Paystack checkout
      final success = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => PaystackWebView(
            url: init.authorizationUrl,
            reference: init.reference, // ✅ use real reference from Paystack
            amount: amount,
          ),
        ),
      );

      // You can rely on the webhook to update the wallet;
      // this screen just shows the UX result.
      if (success == true) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentResponseScreen(
              isSuccess: true,
              message:
                  "Your payment was captured. Your balance will update shortly.",
              amount: amount,
              reference: init.reference,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentResponseScreen(
            isSuccess: false,
            message: "Transaction failed. Please try again.",
            amount: double.tryParse(amountController.text.trim()) ?? 0,
            reference: "—",
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
              validator: (value) => (value == null || value.isEmpty)
                  ? 'This field is required'
                  : null,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1.5),
            CustomTextField(
              hintText: 'user@example.com',
              prefixIcon: Icons.email_outlined,
              label: 'Enter Email *',
              textInputType: TextInputType.emailAddress,
              controller: emailController,
              validator: (value) => (value == null || value.isEmpty)
                  ? 'This field is required'
                  : null,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomButton(
                    onTap: isLoading
                        ? () => ()
                        : () {
                            _startTransaction(); // fire & forget
                          },
                    margin: const EdgeInsets.fromLTRB(10, 0, 10, 10.0),
                    title: 'Proceed to Paystack',
                  ),
                  if (isLoading)
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
