import 'package:flutter/widgets.dart';

class LayoutConstants {
  static const EdgeInsets workspacePadding =
      EdgeInsets.symmetric(horizontal: 16);
  static const EdgeInsets padding20Horizontal =
      EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 20.0);
  static const EdgeInsets padding16Horizontal =
      EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0);
  static const EdgeInsets padding10Horizontal =
      EdgeInsets.fromLTRB(10.0, 2.0, 10.0, 10.0);

  // Vertical spacing scale used by transaction/sale/contact forms.
  // Replaces ad-hoc `SizedBox(height: SizeConfig.heightMultiplier * 1.5/2)`
  // calls so spacing rhythm is consistent across the form surfaces.
  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 12.0;
  static const double spaceLg = 16.0;
  static const double spaceXl = 24.0;

  // Minimum touch target per Design Quality Gate accessibility minimum.
  static const double minTouchTarget = 44.0;
}
