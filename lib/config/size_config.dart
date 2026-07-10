import 'package:flutter/widgets.dart';

class SizeConfig {
  static double screenWidth = 0;
  static double screenHeight = 0;
  static double blockSizeHorizontal = 0;
  static double blockSizeVertical = 0;

  static double textMultiplier = 0;
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

    // Typography must not collapse when the device rotates. The previous
    // height-based multiplier made all copy roughly half-sized in landscape.
    // A bounded width-based token keeps phone typography stable while the
    // framework's TextScaler still honours the user's accessibility setting.
    textMultiplier = (screenWidth / 50).clamp(7.5, 9.0).toDouble();
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
