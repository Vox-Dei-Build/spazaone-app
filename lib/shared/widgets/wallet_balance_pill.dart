import 'package:pasella/design/spaza_tokens.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/shared/billing/wallet_balance_provider.dart';
import 'package:provider/provider.dart';
import 'package:pasella/utils/currency_util.dart';

@immutable
class WalletBalancePresentation {
  const WalletBalancePresentation({
    required this.balance,
    this.salesBalance = 0,
    this.isLoading = false,
    this.isShared = false,
  });

  final double balance;
  final double salesBalance;
  final bool isLoading;
  final bool isShared;
}

/// Always-visible wallet entry point in the app header.
///
/// Shows the live `virtualBalance` (e.g. `R45.20`), tints orange when the
/// balance falls below [lowBalanceThreshold], and renders a green "sales
/// proceeds" dot when `salesVirtualBalance > 0` — preserving the signal the
/// previous wallet icon carried.
///
/// Tapping opens [WalletPage] (same as the previous wallet icon).
class WalletBalancePill extends StatelessWidget {
  /// ZAR threshold under which the pill takes a low-balance tint.
  static const double lowBalanceThreshold = 5.0;

  const WalletBalancePill({
    Key? key,
    this.compact = false,
    this.presentation,
  }) : super(key: key);

  /// Keeps the balance legible in narrow headers without adding another row.
  /// The full billing context remains available through semantics and tap.
  final bool compact;

  /// Optional immutable presentation for previews and deterministic layout
  /// tests. Live app headers leave this null and watch the wallet provider.
  final WalletBalancePresentation? presentation;

  @override
  Widget build(BuildContext context) {
    final wallet =
        presentation == null ? context.watch<WalletBalanceProvider>() : null;
    final balance = presentation?.balance ?? wallet!.virtualBalance;
    final salesBalance =
        presentation?.salesBalance ?? wallet!.salesVirtualBalance;
    final isLoading = presentation?.isLoading ?? wallet!.isLoading;
    final isShared = presentation?.isShared ?? wallet!.sharedCampaignCredits;
    final bool isLow = balance < lowBalanceThreshold;

    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveCompact = compact ||
            (constraints.hasBoundedWidth && constraints.maxWidth <= 96);

        return Semantics(
          button: true,
          label: '${isShared ? 'Shared SpazaOne balance' : 'SpazaOne balance'} '
              '${CurrencyUtil.format(balance)}'
              '${isLow ? '. Low balance. Opens Add money' : ''}',
          excludeSemantics: true,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  // PAS-UX-WTC: when balance is low, sending the merchant
                  // directly to the Top-Up tab matches the visible warning
                  // tint; otherwise open the Account tab first for billing setup.
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WalletPage(
                        initialTab: isLow
                            ? WalletInitialTab.topUp
                            : WalletInitialTab.account,
                      ),
                    ),
                  );
                },
                child: _PillBody(
                  isLoading: isLoading,
                  balance: balance,
                  isLow: isLow,
                  isShared: isShared,
                  compact: effectiveCompact,
                ),
              ),
              if (salesBalance > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Icon(
                      Icons.circle,
                      color: SpazaColors.action,
                      size: SizeConfig.imageSizeMultiplier * 2.5,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PillBody extends StatelessWidget {
  const _PillBody({
    required this.isLoading,
    required this.balance,
    required this.isLow,
    required this.isShared,
    required this.compact,
  });

  final bool isLoading;
  final double balance;
  final bool isLow;
  final bool isShared;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bg =
        isLow ? Colors.orange.withValues(alpha: 0.12) : SpazaColors.subtle;
    final border = isLow ? Colors.orange : SpazaColors.border;
    final fg = isLow ? Colors.orange.shade800 : SpazaColors.heading;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.account_balance_wallet_outlined,
          size: compact ? 15 : SizeConfig.imageSizeMultiplier * 4.2,
          color: fg,
        ),
        SizedBox(
          width: compact ? 3 : SizeConfig.imageSizeMultiplier * 1.5,
        ),
        isLoading
            ? SizedBox(
                width: compact
                    ? SizeConfig.imageSizeMultiplier * 12
                    : SizeConfig.imageSizeMultiplier * 8,
                height: SizeConfig.textMultiplier * 1.6,
                child: const _Shimmer(),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    CurrencyUtil.format(balance),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.7,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                  if (isShared) ...[
                    SizedBox(width: SizeConfig.imageSizeMultiplier),
                    Icon(
                      Icons.link_rounded,
                      size: SizeConfig.imageSizeMultiplier * 3.2,
                      color: fg,
                    ),
                  ],
                  // On narrow headers the orange treatment is the compact
                  // add-money affordance; the full label remains in semantics.
                  if (isLow && !compact) ...[
                    SizedBox(width: SizeConfig.imageSizeMultiplier * 1.5),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: SizeConfig.imageSizeMultiplier * 1.5,
                        vertical: SizeConfig.heightMultiplier * 0.2,
                      ),
                      decoration: BoxDecoration(
                        color: fg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Add money',
                        style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 1.2,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                  if (isLow && compact) ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.arrow_upward_rounded,
                      size: 15,
                      color: fg,
                    ),
                  ],
                ],
              ),
      ],
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * (compact ? 2 : 3),
        vertical: compact ? 4 : SizeConfig.heightMultiplier * 0.9,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border, width: 0.8),
      ),
      child:
          compact ? FittedBox(fit: BoxFit.scaleDown, child: content) : content,
    );
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer();

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(
              alpha: 0.08 + (_ctrl.value * 0.08),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      },
    );
  }
}
