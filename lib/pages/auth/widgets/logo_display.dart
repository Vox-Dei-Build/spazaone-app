import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart'; // Ensure SizeConfig is imported

class LogoDisplay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return Column(
      mainAxisAlignment: MainAxisAlignment.center, // Center align the contents
      children: <Widget>[
        Image.asset(
          'assets/images/logo.png',
          width: SizeConfig.imageSizeMultiplier * 25, // Responsive width
          height: SizeConfig.imageSizeMultiplier * 25, // Responsive height
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 2), // Responsive spacing
        Text(
          'Pasella',
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 3, // Responsive font size
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
