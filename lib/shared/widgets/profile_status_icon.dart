import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

class ProfileStatusIcon extends StatelessWidget {
  final bool isEnabled;
  final IconData enabledIcon;
  final IconData disabledIcon;
  final Color enabledColor;
  final Color disabledColor;

  const ProfileStatusIcon({
    Key? key,
    required this.isEnabled,
    required this.enabledIcon,
    required this.disabledIcon,
    this.enabledColor = Colors.green,
    this.disabledColor = Colors.red,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Icon(
      isEnabled ? enabledIcon : disabledIcon,
      color: isEnabled ? enabledColor : disabledColor,
      size: SizeConfig.imageSizeMultiplier * 3,
    );
  }
}
