import 'package:flutter/material.dart';

/// Production brand colours with neutral surfaces and consistent spacing.
/// Navy identifies navigation; green marks actions and confirmed success.
abstract final class SpazaColors {
  static const action = Color(0xFF1C863B);
  static const navy = Color(0xFF2B325F);
  static const heading = navy;
  static const accent = Color(0xFFEBCB58);
  static const ink = Color(0xFF363A3F);
  static const muted = Color(0xFF686A77);
  static const canvas = Color(0xFFFAFAFA);
  static const surface = Colors.white;
  static const subtle = Color(0xFFF3F4F6);
  static const border = Color(0xFFE4E5EA);
  static const outline = Color(0xFFB6B8C2);
  static const selected = Color(0xFFEAEBF2);
  static const successSurface = Color(0xFFEAF3EC);
  static const error = Color(0xFFB3261E);
}

abstract final class SpazaSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class SpazaRadius {
  static const small = 8.0;
  static const control = 16.0;
  static const surface = 20.0;
  static const sheet = 24.0;
}

/// Match an icon to a job once, rather than choosing a different metaphor on
/// each screen. Brand logos (such as WhatsApp) remain their official marks.
abstract final class SpazaIcons {
  static const customers = Icons.people_outline_rounded;
  static const products = Icons.inventory_2_outlined;
  static const sales = Icons.receipt_long_outlined;
  static const activity = Icons.history_rounded;
  static const shop = Icons.storefront_outlined;
  static const wallet = Icons.account_balance_wallet_outlined;
  static const settings = Icons.settings_outlined;
  static const options = Icons.tune_rounded;
  static const search = Icons.search_rounded;
  static const add = Icons.add_rounded;
  static const back = Icons.arrow_back_rounded;
  static const next = Icons.chevron_right_rounded;
  static const close = Icons.close_rounded;
  static const help = Icons.help_outline_rounded;
  static const privacy = Icons.shield_outlined;
  static const notifications = Icons.notifications_outlined;
  static const signOut = Icons.logout_rounded;
  static const delete = Icons.delete_outline_rounded;
}
