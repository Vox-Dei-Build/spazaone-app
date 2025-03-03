import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart'; // Ensure SizeConfig is imported

class LogoDisplay extends StatelessWidget {
  const LogoDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return Column(
      mainAxisAlignment: MainAxisAlignment.center, // Center align the contents
      children: <Widget>[
        Icon(
          Icons.shopping_cart_outlined,
          color: Colors.orangeAccent,
          size: SizeConfig.imageSizeMultiplier * 24,
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
