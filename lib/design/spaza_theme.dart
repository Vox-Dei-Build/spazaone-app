import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

ThemeData buildSpazaTheme() {
  const scheme = ColorScheme.light(
    primary: SpazaColors.action,
    onPrimary: Colors.white,
    primaryContainer: SpazaColors.successSurface,
    onPrimaryContainer: SpazaColors.action,
    secondary: SpazaColors.heading,
    onSecondary: Colors.white,
    secondaryContainer: SpazaColors.selected,
    onSecondaryContainer: SpazaColors.heading,
    tertiary: SpazaColors.accent,
    onTertiary: SpazaColors.ink,
    error: SpazaColors.error,
    onError: Colors.white,
    surface: SpazaColors.surface,
    onSurface: SpazaColors.ink,
    onSurfaceVariant: SpazaColors.muted,
    outline: SpazaColors.outline,
    outlineVariant: SpazaColors.border,
    surfaceContainerLowest: SpazaColors.surface,
    surfaceContainerLow: SpazaColors.canvas,
    surfaceContainer: SpazaColors.subtle,
    surfaceContainerHigh: SpazaColors.subtle,
    surfaceContainerHighest: SpazaColors.subtle,
    surfaceTint: Colors.transparent,
  );
  const baseText = TextTheme(
    displayLarge:
        TextStyle(fontSize: 36, fontWeight: FontWeight.w700, height: 1.15),
    displayMedium:
        TextStyle(fontSize: 32, fontWeight: FontWeight.w700, height: 1.15),
    displaySmall:
        TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2),
    headlineLarge:
        TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2),
    headlineMedium:
        TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.2),
    headlineSmall:
        TextStyle(fontSize: 27, fontWeight: FontWeight.w500, height: 1.25),
    titleLarge:
        TextStyle(fontSize: 22, fontWeight: FontWeight.w500, height: 1.3),
    titleMedium:
        TextStyle(fontSize: 18, fontWeight: FontWeight.w500, height: 1.35),
    titleSmall:
        TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.4),
    bodyLarge:
        TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5),
    bodyMedium:
        TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5),
    bodySmall:
        TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.45),
    labelLarge:
        TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.2),
    labelMedium:
        TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.2),
    labelSmall:
        TextStyle(fontSize: 11, fontWeight: FontWeight.w500, height: 1.2),
  );
  final text = baseText.apply(fontFamily: 'SpazaSans');
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(SpazaRadius.control),
  );
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(SpazaRadius.control),
    borderSide: const BorderSide(color: SpazaColors.border),
  );
  return ThemeData(
    useMaterial3: true,
    // Bundled fonts keep iOS, Android and web consistent and work offline.
    fontFamily: 'SpazaSans',
    colorScheme: scheme,
    scaffoldBackgroundColor: SpazaColors.canvas,
    textTheme: text.apply(
        bodyColor: SpazaColors.ink, displayColor: SpazaColors.heading),
    iconTheme: const IconThemeData(color: SpazaColors.muted, size: 22),
    dividerTheme: const DividerThemeData(
        color: SpazaColors.border, thickness: 1, space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: SpazaColors.canvas,
      foregroundColor: SpazaColors.heading,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 56,
      titleSpacing: 16,
      titleTextStyle: TextStyle(
          fontFamily: 'SpazaSans',
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: SpazaColors.heading),
    ),
    cardTheme: CardTheme(
      color: SpazaColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
        side: const BorderSide(color: SpazaColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
      minimumSize: const Size(48, 52),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: controlShape,
      textStyle: text.labelLarge,
    )),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
      backgroundColor: SpazaColors.action,
      foregroundColor: Colors.white,
      disabledBackgroundColor: SpazaColors.border,
      disabledForegroundColor: SpazaColors.muted,
      minimumSize: const Size(48, 52),
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: controlShape,
      textStyle: text.labelLarge,
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
      foregroundColor: SpazaColors.heading,
      minimumSize: const Size(48, 52),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      side: const BorderSide(color: SpazaColors.border),
      shape: controlShape,
      textStyle: text.labelLarge,
    )),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
      foregroundColor: SpazaColors.heading,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      shape: controlShape,
      textStyle: text.labelLarge,
    )),
    iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
      foregroundColor: SpazaColors.muted,
      minimumSize: const Size(48, 48),
      iconSize: 22,
    )),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SpazaColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      disabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: SpazaColors.heading, width: 1.5)),
      errorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: SpazaColors.error)),
      focusedErrorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: SpazaColors.error, width: 1.5)),
      labelStyle: text.bodyMedium!.copyWith(color: SpazaColors.muted),
      hintStyle: text.bodyMedium!.copyWith(color: SpazaColors.muted),
      errorStyle: text.bodySmall!.copyWith(color: SpazaColors.error),
      errorMaxLines: 3,
      helperMaxLines: 3,
      prefixIconColor: SpazaColors.muted,
      suffixIconColor: SpazaColors.muted,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minLeadingWidth: 22,
      horizontalTitleGap: 12,
      iconColor: SpazaColors.muted,
      textColor: SpazaColors.ink,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: SpazaColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(SpazaRadius.sheet))),
      dragHandleColor: SpazaColors.outline,
    ),
    dialogTheme: DialogTheme(
      backgroundColor: SpazaColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpazaRadius.sheet)),
      titleTextStyle: text.titleLarge!
          .copyWith(fontFamily: 'SpazaSans', color: SpazaColors.heading),
      contentTextStyle: text.bodyMedium!
          .copyWith(fontFamily: 'SpazaSans', color: SpazaColors.ink),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: SpazaColors.surface,
      surfaceTintColor: Colors.transparent,
      height: 72,
      elevation: 0,
      indicatorColor: SpazaColors.navy,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? SpazaColors.accent
              : SpazaColors.navy)),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: 'SpazaSans',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w500
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? SpazaColors.heading
                : SpazaColors.muted,
          )),
    ),
    tabBarTheme: const TabBarTheme(
      labelColor: SpazaColors.heading,
      unselectedLabelColor: SpazaColors.muted,
      indicatorColor: SpazaColors.heading,
      dividerColor: SpazaColors.border,
      labelStyle: TextStyle(
          fontFamily: 'SpazaSans', fontSize: 14, fontWeight: FontWeight.w500),
      unselectedLabelStyle: TextStyle(
          fontFamily: 'SpazaSans', fontSize: 14, fontWeight: FontWeight.w400),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: SpazaColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: controlShape,
      contentTextStyle: text.bodyMedium!
          .copyWith(fontFamily: 'SpazaSans', color: Colors.white),
    ),
  );
}
