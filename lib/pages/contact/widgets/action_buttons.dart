import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/contact/add_credit/add_credit.dart';
import 'package:pasella/pages/contact/add_payment/add_payment.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';

class AddCreditPaymentButtons extends StatelessWidget {
  final String customerName;
  final String customerId;
  final String? mobileNumber;

  const AddCreditPaymentButtons(
      {super.key,
      required this.customerName,
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
            title: 'Pay Later',
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
            height: SizeConfig.heightMultiplier * 5,
            color: Colors.red,
            icon: Icons.arrow_downward,
            iconSize: SizeConfig.imageSizeMultiplier * 4,
            margin: EdgeInsets.symmetric(
                horizontal: SizeConfig.imageSizeMultiplier * 3),
            fontSize: SizeConfig.textMultiplier * 1.8, // Adjust font size
          ),
        ),
        SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
        Expanded(
          child: CustomButton(
            title: 'Pay Now',
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
            height: SizeConfig.heightMultiplier * 5,
            color: Colors.green,
            margin: EdgeInsets.symmetric(
                horizontal: SizeConfig.imageSizeMultiplier * 3),
            icon: Icons.arrow_upward,
            iconSize: SizeConfig.imageSizeMultiplier * 4,
            fontSize: SizeConfig.textMultiplier * 1.8, // Adjust font size
          ),
        ),
      ],
    );
  }
}
