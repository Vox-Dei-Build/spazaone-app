import 'package:flutter/widgets.dart';

class SizeConfig {
  static double screenWidth = 0;
  static double screenHeight = 0;
  static double blockSizeHorizontal = 0;
  static double blockSizeVertical = 0;

  static double textMultiplier = 8;
  static double imageSizeMultiplier = 0;
  static double heightMultiplier = 0;

  static bool isPortrait = true;
  static bool isMobilePortrait = false;

  void init(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    screenWidth = mediaQuery.size.width;
    screenHeight = mediaQuery.size.height;
    blockSizeHorizontal = screenWidth / 100;
    blockSizeVertical = screenHeight / 100;

    // Legacy callers retain their scale without changing text size between
    // phones, tablets or rotations. New UI uses the shared TextTheme directly.
    // Flutter's TextScaler remains responsible for accessibility text sizing.
    textMultiplier = 8;
    // Image and spacing tokens should also survive rotation. Scaling from
    // the long edge made icons and horizontal padding roughly double in
    // landscape. The bounded shortest edge stays stable on phones and avoids
    // oversized controls on tablets.
    imageSizeMultiplier =
        (mediaQuery.size.shortestSide / 100).clamp(3.2, 4.5).toDouble();
    heightMultiplier = blockSizeVertical;

    isPortrait = mediaQuery.orientation == Orientation.portrait;
    isMobilePortrait = isPortrait && screenWidth < 450;
  }
}
