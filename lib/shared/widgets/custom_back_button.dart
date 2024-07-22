import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasella/config/size_config.dart';

class CustomBackButton extends StatelessWidget {
  const CustomBackButton({
    super.key,
    required this.title,
    this.trailing,
    this.onBack = true,
  });

  final String title;
  final Widget? trailing;
  final bool? onBack;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: SizeConfig.imageSizeMultiplier * 4,
            right: SizeConfig.imageSizeMultiplier * 4,
            top: SizeConfig.heightMultiplier * 2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (onBack == true)
                IconButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    SystemChannels.textInput.invokeMethod('TextInput.hide');
                    Navigator.pop(context);
                  },
                  icon: Icon(
                    Icons.arrow_back_ios,
                    size: SizeConfig.imageSizeMultiplier *
                        7, // Responsive icon size
                  ),
                )
              else
                SizedBox(
                    width: SizeConfig.imageSizeMultiplier *
                        7), // Adjust width for alignment
              Expanded(
                child: Center(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize:
                          SizeConfig.textMultiplier * 3, // Responsive font size
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              if (trailing != null)
                trailing!
              else
                SizedBox(
                    width: SizeConfig.imageSizeMultiplier *
                        7), // Adjust width for alignment
            ],
          ),
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 3), // Responsive spacing
      ],
    );
  }
}
