import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_theme.dart';
import 'package:pasella/design/spaza_tokens.dart';

const kPrimaryColor = SpazaColors.action;

const kSecondaryColor = SpazaColors.accent;

const kTertiaryColor = SpazaColors.heading;

const kHighLightColor = SpazaColors.subtle;

const kSecondaryAccent = SpazaColors.muted;

const kTextFieldStyle = TextStyle(
  fontSize: 16.0,
  fontWeight: FontWeight.w400,
  height: 1.4,
);

const kLabelStyle = TextStyle(
  color: kSecondaryAccent,
  fontSize: 13.0,
  fontWeight: FontWeight.bold,
);

const kSectionHeaderStyle = TextStyle(
  fontSize: 18.0,
  fontWeight: FontWeight.w500,
);

const kSubTitleStyle = TextStyle(
  color: Color(0xff757575),
  fontSize: 13.0,
  fontWeight: FontWeight.w500,
);

class WaBrandColour {
  static const tealGreenDarker = Color(0xFF075E54);
  static const tealGreenLighter = Color(0xFF128C7E);
  static const lightGreen = Color(0xFF25D366);
  static const white = Color(0xFFFFFFFF);
  static const outgoingChatBubble = Color(0xFFDCF8C6);
  static const checkmarkBlue = Color(0xFF34B7F1);
  static const time = Color(0xFF808080);
  static const chatBackground = Color(0xFFECE5DD);
}

final kCustomThemeData = buildSpazaTheme();
