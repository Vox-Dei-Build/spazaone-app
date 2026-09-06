import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/widgets/private_region.dart';
import 'package:provider/provider.dart';

class CustomerBalanceHero extends StatelessWidget {
  const CustomerBalanceHero({super.key});

  @override
  Widget build(BuildContext context) =>
      Consumer<CustomerBalanceSummaryProvider>(
        builder: (context, provider, _) {
          final summary = provider.customerBalanceSummary;
          return CustomerBalanceCard(
            balance: summary.netBalance,
            creditCount: summary.creditCount,
            paymentCount: summary.paymentCount,
          );
        },
      );
}

/// The customer balance presentation, usable without a live ledger provider.
class CustomerBalanceCard extends StatelessWidget {
  const CustomerBalanceCard({
    super.key,
    required this.balance,
    required this.creditCount,
    required this.paymentCount,
  });

  final double balance;
  final int creditCount;
  final int paymentCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _BalanceState.from(balance);
    return PrivateRegion(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: SpazaColors.border),
          borderRadius: BorderRadius.circular(SpazaRadius.surface),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaled = MediaQuery.textScalerOf(context).scale(14) > 19;
            final primary = Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: state.accent.withValues(alpha: .08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(state.icon, color: state.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.eyebrow,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: state.accent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Semantics(
                        label:
                            '${state.eyebrow} ${CurrencyUtil.format(balance.abs())}',
                        excludeSemantics: true,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            CurrencyUtil.format(balance.abs()),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: state.accent,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final counts = _BalanceCounts(
              creditCount: creditCount,
              paymentCount: paymentCount,
            );
            if (constraints.maxWidth < 330 || scaled) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  primary,
                  const SizedBox(height: 10),
                  counts,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: primary),
                const SizedBox(width: 12),
                counts,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BalanceCounts extends StatelessWidget {
  const _BalanceCounts({
    required this.creditCount,
    required this.paymentCount,
  });

  final int creditCount;
  final int paymentCount;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 4,
        alignment: WrapAlignment.end,
        children: [
          _Count(
            icon: Icons.arrow_downward_rounded,
            label: '$creditCount added',
            color: SpazaColors.error,
          ),
          _Count(
            icon: Icons.arrow_upward_rounded,
            label: '$paymentCount paid',
            color: SpazaColors.action,
          ),
        ],
      );
}

class _Count extends StatelessWidget {
  const _Count({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 3),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
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
        accent: SpazaColors.error,
        icon: Icons.arrow_downward_rounded,
      );
    }
    if (balance > 0) {
      return const _BalanceState._(
        eyebrow: 'AHEAD',
        accent: SpazaColors.action,
        icon: Icons.arrow_upward_rounded,
      );
    }
    return const _BalanceState._(
      eyebrow: 'SETTLED',
      accent: SpazaColors.muted,
      icon: Icons.check_rounded,
    );
  }
}
