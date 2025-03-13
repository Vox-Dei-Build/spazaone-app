import 'package:flutter/material.dart';
import 'package:pasella/pages/wallet/widgets/paystack_form.dart';

class TopUpTab extends StatelessWidget {
  const TopUpTab({Key? key}) : super(key: key);

  /// Open the Paystack Form screen
  void _openPaystackForm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const PaystackFormScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => _openPaystackForm(context),
        child: const Text("Top Up with Paystack"),
      ),
    );
  }
}
