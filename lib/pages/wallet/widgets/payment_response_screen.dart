import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

class PaymentResponseScreen extends StatelessWidget {
  final bool isSuccess;
  final String message;
  final double amount;
  final String reference;

  const PaymentResponseScreen({
    Key? key,
    required this.isSuccess,
    required this.message,
    required this.amount,
    required this.reference,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(SizeConfig.heightMultiplier * 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.error,
              color: isSuccess ? Colors.green : Colors.red,
              size: SizeConfig.imageSizeMultiplier * 15,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Text(
              isSuccess ? "Payment Successful" : "Payment Failed",
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 2.5,
                fontWeight: FontWeight.bold,
                color: isSuccess ? Colors.green : Colors.red,
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.8,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 3),
            _buildDetailRow("Amount", "R${amount.toStringAsFixed(2)}"),
            _buildDetailRow("Reference", reference),
            SizedBox(height: SizeConfig.heightMultiplier * 4),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("OK"),
            ),
          ],
        ),
      ),
    );
  }

  /// Helper Widget for details
  Widget _buildDetailRow(String title, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 1.2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.8,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.8,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
