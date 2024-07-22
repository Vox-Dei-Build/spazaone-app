import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  const InfoRow({
    Key? key,
    required this.label,
    required this.value,
    this.labelStyle,
    this.valueStyle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 0.5,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "$label: ",
            style: labelStyle ??
                TextStyle(
                  color: Colors.black,
                  fontSize: SizeConfig.textMultiplier * 1.8,
                ),
          ),
          Text(
            value,
            style: valueStyle ??
                TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: SizeConfig.textMultiplier * 1.8,
                ),
          ),
        ],
      ),
    );
  }
}
