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

  /// Injectable chrome used by narrow-layout widget tests. Production callers
  /// leave these null and receive the live wallet/connectivity widgets.
  final Widget? walletWidget;
  final Widget? connectivityWidget;
  final VoidCallback? onSettingsTap;

  const PageHeader({
    Key? key,
    this.onSearchTap,
    this.actionWidget,
    this.trailingWidget,
    this.walletWidget,
    this.connectivityWidget,
    this.onSettingsTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasPageAction = onSearchTap != null ||
            actionWidget != null ||
            trailingWidget != null;
        final scaledBody = MediaQuery.textScalerOf(context).scale(14);
        final veryNarrow = constraints.maxWidth <= 340;
        final compact = constraints.maxWidth <= 440 || scaledBody > 19;
        final iconSize = (SizeConfig.imageSizeMultiplier * 5).clamp(18.0, 22.0);
        final brandWidth = veryNarrow && hasPageAction
            ? 74.0
            : compact
                ? 88.0
                : 120.0;
        final walletMaxWidth = veryNarrow ? 80.0 : (compact ? 96.0 : 180.0);
        final pillGap = compact ? 3.0 : SizeConfig.imageSizeMultiplier * 2;
        final tightGap = compact ? 0.0 : SizeConfig.imageSizeMultiplier * 0.5;

        Widget compactAction(Widget child) => SizedBox(
              width: compact ? 44 : null,
              height: 44,
              child: child,
            );

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 1,
          ),
          child: Row(
            children: [
              // ── Brand ────────────────────────────────────────────────
              SizedBox(
                key: const ValueKey('page-header-brand'),
                width: brandWidth,
                height: 30,
                child: Image.asset(
                  'assets/images/spazaone_logo_horizontal.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  semanticLabel: 'Spaza One',
                ),
              ),
              const Spacer(),

              // ── Page-scoped actions ──────────────────────────────────
              if (onSearchTap != null)
                compactAction(
                  IconButton(
                    icon:
                        Icon(Icons.search, color: Colors.black, size: iconSize),
                    onPressed: onSearchTap,
                    tooltip: 'Search',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                  ),
                ),
              if (actionWidget != null)
                // Strip Expanded wrappers from caller-supplied actionWidgets so
                // they don't gobble the breathing room before the wallet pill.
                // (Several pages historically wrap icons in Expanded — that
                // collides the icon with the pill and also breaks Row layout
                // when combined with Flexible siblings.)
                compactAction(
                  actionWidget is Expanded
                      ? (actionWidget as Expanded).child
                      : actionWidget!,
                ),

              // ── Account / value (wallet pill, with breathing room) ──
              SizedBox(width: pillGap),
              ConstrainedBox(
                key: const ValueKey('page-header-wallet'),
                constraints: BoxConstraints(maxWidth: walletMaxWidth),
                child: walletWidget ?? WalletBalancePill(compact: compact),
              ),
              SizedBox(width: pillGap),

              // ── System cluster (settings + connectivity) ────────────
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  icon: Icon(Icons.settings_outlined,
                      color: Colors.black, size: iconSize),
                  onPressed: onSettingsTap ??
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsPage(),
                          ),
                        );
                      },
                  tooltip: 'Settings',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 44, height: 44),
                ),
              ),
              SizedBox(width: tightGap),
              connectivityWidget ?? const ConnectivityIndicator(),

              // ── Optional trailing slot (true far-right) ────────────
              if (trailingWidget != null) ...[
                SizedBox(width: tightGap),
                compactAction(trailingWidget!),
              ],
            ],
          ),
        );
      },
    );
  }
}
