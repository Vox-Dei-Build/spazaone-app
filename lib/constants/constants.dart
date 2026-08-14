import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

const kPrimaryColor = Color(0xff1c863b);

const kSecondaryColor = Color(0xffEBCB58);

const kTertiaryColor = Color(0xff2B325F);

const kHighLightColor = Color(0xffeef4ef);

const kSecondaryAccent = Color(0xff686A77);

const kTextFieldStyle = TextStyle(
  fontSize: 14.5,
  fontWeight: FontWeight.w500,
  height: 1.4,
);

const kLabelStyle = TextStyle(
  color: kSecondaryAccent,
  fontSize: 13.0,
  fontWeight: FontWeight.bold,
);

const kSectionHeaderStyle = TextStyle(
  fontSize: 17.0,
  fontWeight: FontWeight.bold,
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

final kCustomThemeData = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.light(
    primary: kPrimaryColor,
    surfaceTint: Colors.white,
  ),
  iconTheme: const IconThemeData(color: kTertiaryColor),
  // PAS-UX-rel: standardise Card chrome across the app so the
  // onboarding surfaces stop rolling their own borders/elevations.
  // 12-dp corners match M3's baseline and read as more premium than
  // the 8-dp chrome the older widgets shipped with.
  cardTheme: CardTheme(
    elevation: 0.5,
    surfaceTintColor: kPrimaryColor,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  navigationBarTheme: NavigationBarThemeData(
    elevation: 10.0,
    height: 70.0,
    iconTheme: MaterialStateProperty.resolveWith((states) {
      return IconThemeData(
        color: states.contains(MaterialState.selected)
            ? kSecondaryColor
            : kTertiaryColor,
      );
    }),
    indicatorColor: kTertiaryColor,
    backgroundColor: Colors.grey.shade100,
    surfaceTintColor: Colors.white,
    labelTextStyle: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.selected)) {
        return TextStyle(
          fontSize: SizeConfig.textMultiplier * 1.5,
          fontWeight: FontWeight.w500,
        );
      }
      return TextStyle(
        fontSize: SizeConfig.textMultiplier * 1.5,
        fontWeight: FontWeight.normal,
      );
    }),
  ),
  tabBarTheme: const TabBarTheme(
    // Tabs communicate location. Reserve green for primary actions and
    // confirmed success so it keeps its meaning throughout the app.
    labelColor: kTertiaryColor,
    indicatorColor: kTertiaryColor,
    dividerColor: kHighLightColor,
    labelStyle: TextStyle(fontWeight: FontWeight.bold),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    prefixIconColor: Colors.grey,
    enabledBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: Colors.grey),
    ),
  ),
);
