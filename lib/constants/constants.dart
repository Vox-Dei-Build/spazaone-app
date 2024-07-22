import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

const kPrimaryColor = Color(0xff1c863b);

const kSecondaryColor = Color(0xffEBCB58);

const kTertiaryColor = Color(0xff2B325F);

const kHighLightColor = Color(0xffeef4ef);

const kSecondaryAccent = Color(0xff757784);

const kTextFieldStyle = TextStyle(
  fontSize: 14.5,
  fontWeight: FontWeight.w500,
  height: 1.4,
);

const kLabelStyle = TextStyle(
  color: Color(0xff757784),
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

final kCustomThemeData = ThemeData(
  useMaterial3: true,
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  splashFactory: NoSplash.splashFactory,
  colorScheme: const ColorScheme.light(
      primary: kPrimaryColor, surfaceTint: Colors.white),
  iconTheme: const IconThemeData(color: kTertiaryColor),
  navigationBarTheme: NavigationBarThemeData(
    elevation: 10.0,
    height: 70.0,
    iconTheme: const MaterialStatePropertyAll(
      IconThemeData(
        color: kSecondaryColor,
      ),
    ),
    indicatorColor: kTertiaryColor,
    backgroundColor: Colors.grey.shade100,
    surfaceTintColor: Colors.white,
    labelTextStyle: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.selected)) {
        return TextStyle(
          fontSize: SizeConfig.textMultiplier * 2,
          fontWeight: FontWeight.w500,
        );
      }
      return TextStyle(
        fontSize: SizeConfig.textMultiplier * 2,
        fontWeight: FontWeight.normal,
      );
    }),
  ),
  tabBarTheme: const TabBarTheme(
    labelColor: kPrimaryColor,
    indicatorColor: kPrimaryColor,
    dividerColor: kHighLightColor,
    labelStyle: TextStyle(fontWeight: FontWeight.bold),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    prefixIconColor: Colors.grey,
    enabledBorder: UnderlineInputBorder(
      borderSide: BorderSide(
        color: Colors.grey,
      ),
    ),
  ),
);
