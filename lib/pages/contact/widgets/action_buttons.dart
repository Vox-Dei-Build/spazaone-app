import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/contact/add_credit/add_credit.dart';
import 'package:pasella/pages/contact/add_payment/add_payment.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';

class AddCreditPaymentButtons extends StatelessWidget {
  final String customerName;
  final String customerId;
  final String? mobileNumber;

  AddCreditPaymentButtons(
      {required this.customerName,
      required this.customerId,
      this.mobileNumber});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Expanded(
          child: CustomButton(
            title: 'Credit',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddCreditScreen(
                      customerName: customerName,
                      customerId: customerId,
                      mobileNumber: mobileNumber),
                ),
              );
            },
            color: Colors.red,
            icon: Icons.arrow_downward,
            fontSize: SizeConfig.textMultiplier * 1.8, // Adjust font size
          ),
        ),
        SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
        Expanded(
          child: CustomButton(
            title: 'Payment',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddPaymentScreen(
                      customerName: customerName,
                      customerId: customerId,
                      mobileNumber: mobileNumber),
                ),
              );
            },
            color: Colors.green,
            icon: Icons.arrow_upward,
            fontSize: SizeConfig.textMultiplier * 2, // Adjust font size
          ),
        ),
      ],
    );
  }
}
