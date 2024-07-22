import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';

class TransactionDate extends StatelessWidget {
  final String date;

  TransactionDate(this.date);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 1,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SizeConfig.heightMultiplier * 2),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 2,
            vertical: SizeConfig.heightMultiplier * 1,
          ),
          color: Color(0xffbdbdbd),
          child: Text(
            DateFormat('y MMM d, h:mm a').format(DateTime.parse(date)),
            style: TextStyle(
              fontWeight: FontWeight.w300,
              color: Colors.white,
              fontSize: SizeConfig.textMultiplier * 2,
            ),
          ),
        ),
      ),
    );
  }
}
