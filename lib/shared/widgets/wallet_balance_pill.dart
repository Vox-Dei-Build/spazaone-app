import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/shared/billing/wallet_balance_provider.dart';
import 'package:provider/provider.dart';

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

  const WalletBalancePill({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletBalanceProvider>();
    final bool isLow = wallet.virtualBalance < lowBalanceThreshold;

    return Stack(
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
                  initialTab:
                      isLow ? WalletInitialTab.topUp : WalletInitialTab.account,
                ),
              ),
            );
          },
          child: _PillBody(
            isLoading: wallet.isLoading,
            balance: wallet.virtualBalance,
            isLow: isLow,
          ),
        ),
        if (wallet.salesVirtualBalance > 0)
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
                color: Colors.green,
                size: SizeConfig.imageSizeMultiplier * 2.5,
              ),
            ),
          ),
      ],
    );
  }
}

class _PillBody extends StatelessWidget {
  const _PillBody({
    required this.isLoading,
    required this.balance,
    required this.isLow,
  });

  final bool isLoading;
  final double balance;
  final bool isLow;

  @override
  Widget build(BuildContext context) {
    final bg = isLow
        ? Colors.orange.withOpacity(0.12)
        : Colors.black.withOpacity(0.05);
    final border = isLow ? Colors.orange : Colors.black26;
    final fg = isLow ? Colors.orange.shade800 : Colors.black87;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 3,
        vertical: SizeConfig.heightMultiplier * 0.9,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: SizeConfig.imageSizeMultiplier * 4.2,
            color: fg,
          ),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 1.5),
          isLoading
              ? SizedBox(
                  width: SizeConfig.imageSizeMultiplier * 8,
                  height: SizeConfig.textMultiplier * 1.6,
                  child: const _Shimmer(),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'R${balance.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.7,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                    // PAS-UX-WTC: inline "Top up" affordance so the
                    // low-balance state isn't just a colour change.
                    if (isLow) ...[
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
                          'Top up',
                          style: TextStyle(
                            fontSize: SizeConfig.textMultiplier * 1.2,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ],
      ),
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
            color: Colors.black.withOpacity(0.08 + (_ctrl.value * 0.08)),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      },
    );
  }
}
