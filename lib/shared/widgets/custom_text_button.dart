import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';

class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.title,
    required this.onTap,
    this.color,
    this.margin,
    this.width,
    this.height,
    this.fontSize,
    this.icon,
    this.radius,
  });

  final String title;
  final VoidCallback onTap;
  final Color? color;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final double? fontSize;
  final IconData? icon;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: margin ??
            EdgeInsets.symmetric(
                horizontal: SizeConfig.imageSizeMultiplier * 2),
        height: height ?? SizeConfig.heightMultiplier * 7,
        width: width ?? double.infinity,
        decoration: BoxDecoration(
          color: color ?? kPrimaryColor,
          borderRadius: BorderRadius.circular(
              radius ?? SizeConfig.imageSizeMultiplier * 4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null)
              Padding(
                padding:
                    EdgeInsets.only(right: SizeConfig.imageSizeMultiplier * 2),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: SizeConfig.imageSizeMultiplier * 6,
                ),
              ),
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize ?? SizeConfig.textMultiplier * 2.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
