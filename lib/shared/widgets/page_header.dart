import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/settings/settings.dart';
import 'package:pasella/shared/widgets/connectivity_widget.dart';
import 'package:pasella/shared/widgets/wallet_balance_pill.dart';

/// Top-of-page header.
///
/// Layout, left → right:
///   1. Brand (logo + "SpazaOne")
///   2. Page-scoped actions: optional search, optional `actionWidget`
///   3. Account/value: wallet balance pill (always visible, with breathing
///      room so its rounded shape doesn't visually merge with adjacent icons)
///   4. System: settings + connectivity status
///   5. Optional `trailingWidget` — pinned to the true far right of the
///      header, after the system cluster. Use this when a page has a
///      contextual action that should read as a system-level affordance
///      (e.g. the Stock kebab) rather than competing with the wallet
///      pill in the middle of the row.
///
/// Width strategy: every element renders at its natural size and is sized to
/// fit comfortably even on narrow Android screens (~360dp). The brand is
/// intentionally toned down from a hero-sized title to a header-appropriate
/// size so the always-visible wallet pill, page actions, and system cluster
/// all fit without ellipsizing or overflow.
class PageHeader extends StatelessWidget {
  final VoidCallback? onSearchTap;
  final Widget? actionWidget;

  /// Optional widget rendered at the true far-right of the header, after
  /// the system cluster (settings + connectivity).
  ///
  /// Use this for page-level overflow menus where the user expectation
  /// is "the dots are in the corner". `actionWidget` is positioned
  /// before the wallet pill, which is correct for inline search-style
  /// affordances but reads off-balance for a three-dot menu.
  final Widget? trailingWidget;

  const PageHeader({
    Key? key,
    this.onSearchTap,
    this.actionWidget,
    this.trailingWidget,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final iconSize = SizeConfig.imageSizeMultiplier * 5;
    final pillGap = SizeConfig.imageSizeMultiplier * 2;
    final tightGap = SizeConfig.imageSizeMultiplier * 0.5;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 1,
      ),
      child: Row(
        children: [
          // ── Brand ────────────────────────────────────────────────
          Icon(
            Icons.shopping_cart_outlined,
            color: Colors.orangeAccent,
            size: SizeConfig.imageSizeMultiplier * 8,
          ),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 1),
          Text(
            'SpazaOne',
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 2.6,
              fontWeight: FontWeight.bold,
            ),
          ),

          const Spacer(),

          // ── Page-scoped actions ──────────────────────────────────
          if (onSearchTap != null)
            IconButton(
              icon: Icon(Icons.search, color: Colors.black, size: iconSize),
              onPressed: onSearchTap,
              tooltip: 'Search',
              visualDensity: VisualDensity.compact,
            ),
          if (actionWidget != null)
            // Strip Expanded wrappers from caller-supplied actionWidgets so
            // they don't gobble the breathing room before the wallet pill.
            // (Several pages historically wrap icons in Expanded — that
            // collides the icon with the pill and also breaks Row layout
            // when combined with Flexible siblings.)
            actionWidget is Expanded
                ? (actionWidget as Expanded).child
                : actionWidget!,

          // ── Account / value (wallet pill, with breathing room) ──
          SizedBox(width: pillGap),
          const WalletBalancePill(),
          SizedBox(width: pillGap),

          // ── System cluster (settings + connectivity) ────────────
          IconButton(
            icon: Icon(Icons.settings_outlined,
                color: Colors.black, size: iconSize),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
            tooltip: 'Settings',
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(width: tightGap),
          const ConnectivityIndicator(),

          // ── Optional trailing slot (true far-right) ────────────
          if (trailingWidget != null) ...[
            SizedBox(width: tightGap),
            trailingWidget!,
          ],
        ],
      ),
    );
  }
}
