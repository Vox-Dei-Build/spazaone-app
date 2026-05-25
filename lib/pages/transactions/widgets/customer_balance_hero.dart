// Compact balance hero for the Pay Later screen.
//
// Replaces the heavy three-section `BalanceSummaryCard` footer (icon row +
// stats row + injected CTAs) with a single quiet card that answers the
// only question a merchant actually has when they open a customer
// profile: "How much does this person owe me, right now?"
//
// Visual approach (post-review):
//   The first pass shipped a full-bleed tinted band (red/green/slate
//   washes). On phones those washes dominated the screen and made the
//   page feel "loud" — every customer profile screamed its state. A
//   second pass tried near-white + hairline coloured border, but a
//   border still reads as "tagged thing" rather than a clean surface.
//   We now use a plain white card with a soft drop shadow. Colour
//   lives where it earns its keep: the eyebrow label, the state icon,
//   and the balance amount itself. Everything else stays neutral.
//
// State-aware:
//  - netBalance < 0  -> "Owing"     (red accent, down arrow)
//  - netBalance > 0  -> "In credit" (green accent, up arrow)
//  - netBalance == 0 -> "Settled"   (slate accent, check)
//
// Watches [CustomerBalanceSummaryProvider] directly so it rebuilds every
// time the stream of transactions pushes a fresh snapshot.

import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/widgets/private_region.dart';
import 'package:provider/provider.dart';

class CustomerBalanceHero extends StatelessWidget {
  const CustomerBalanceHero({super.key});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Consumer<CustomerBalanceSummaryProvider>(
      builder: (context, provider, _) {
        final summary = provider.customerBalanceSummary;
        final balance = summary.netBalance;
        final state = _BalanceState.from(balance);

        return PrivateRegion(
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 4,
              vertical: SizeConfig.heightMultiplier * 1.4,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(
                SizeConfig.heightMultiplier * 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Quiet icon — colored glyph on a hairline-tinted circle.
                // The tint here is held to ~6% so it reads as "barely
                // there" rather than a coloured chip.
                Container(
                  width: SizeConfig.imageSizeMultiplier * 10,
                  height: SizeConfig.imageSizeMultiplier * 10,
                  decoration: BoxDecoration(
                    color: state.accent.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    state.icon,
                    color: state.accent,
                    size: SizeConfig.imageSizeMultiplier * 5.5,
                  ),
                ),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.eyebrow,
                        style: TextStyle(
                          color: state.accent,
                          fontSize: SizeConfig.textMultiplier * 1.4,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      SizedBox(height: SizeConfig.heightMultiplier * 0.3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          CurrencyUtil.format(balance.abs()),
                          style: TextStyle(
                            color: state.accent,
                            fontSize: SizeConfig.textMultiplier * 3.2,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                _StatsCluster(
                  creditCount: summary.creditCount,
                  paymentCount: summary.paymentCount,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatsCluster extends StatelessWidget {
  final int creditCount;
  final int paymentCount;

  const _StatsCluster({
    required this.creditCount,
    required this.paymentCount,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: const Color(0xFF6B7280),
      fontSize: SizeConfig.textMultiplier * 1.2,
      fontWeight: FontWeight.w500,
    );
    final valueStyle = TextStyle(
      color: const Color(0xFF111827),
      fontSize: SizeConfig.textMultiplier * 1.6,
      fontWeight: FontWeight.bold,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_downward,
                size: SizeConfig.imageSizeMultiplier * 3,
                color: const Color(0xFFC62828)),
            const SizedBox(width: 4),
            Text('$creditCount', style: valueStyle),
          ],
        ),
        Text('credits', style: labelStyle),
        SizedBox(height: SizeConfig.heightMultiplier * 0.4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_upward,
                size: SizeConfig.imageSizeMultiplier * 3,
                color: const Color(0xFF1B5E20)),
            const SizedBox(width: 4),
            Text('$paymentCount', style: valueStyle),
          ],
        ),
        Text('payments', style: labelStyle),
      ],
    );
  }
}

class _BalanceState {
  final String eyebrow;
  final Color accent;
  final IconData icon;

  const _BalanceState._({
    required this.eyebrow,
    required this.accent,
    required this.icon,
  });

  factory _BalanceState.from(double balance) {
    if (balance < 0) {
      return const _BalanceState._(
        eyebrow: 'OWING',
        accent: Color(0xFFC62828), // red 800
        icon: Icons.arrow_downward_rounded,
      );
    }
    if (balance > 0) {
      return const _BalanceState._(
        eyebrow: 'IN CREDIT',
        accent: Color(0xFF1B5E20), // green 900
        icon: Icons.arrow_upward_rounded,
      );
    }
    return const _BalanceState._(
      eyebrow: 'SETTLED',
      accent: Color(0xFF455A64), // blue-grey 700
      icon: Icons.check_rounded,
    );
  }
}
