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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: SpazaColors.border),
          borderRadius: BorderRadius.circular(SpazaRadius.surface),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(state.icon, color: state.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.eyebrow,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: state.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Semantics(
              label: '${state.eyebrow} ${CurrencyUtil.format(balance.abs())}',
              excludeSemantics: true,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  CurrencyUtil.format(balance.abs()),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: state.accent,
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                Text(
                    '$creditCount ${creditCount == 1 ? 'transaction' : 'transactions'}',
                    style: theme.textTheme.bodySmall),
                Text(
                    '$paymentCount ${paymentCount == 1 ? 'payment' : 'payments'}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
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
        eyebrow: 'AHEAD',
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
