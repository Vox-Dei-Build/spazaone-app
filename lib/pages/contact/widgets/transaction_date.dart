import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';

class TransactionDate extends StatelessWidget {
  final String date;

  const TransactionDate(this.date, {super.key});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 1,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SizeConfig.heightMultiplier * 1),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 1.5,
            vertical: SizeConfig.heightMultiplier * 0.5,
          ),
          color: const Color(0xffbdbdbd),
          child: Text(
            DateFormat('y MMM d, h:mm a').format(DateTime.parse(date)),
            style: TextStyle(
              fontWeight: FontWeight.w300,
              color: Colors.white,
              fontSize: SizeConfig.textMultiplier * 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
