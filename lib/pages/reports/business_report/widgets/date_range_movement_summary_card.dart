import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

class DateRangeMovementSummaryCard extends StatelessWidget {
  const DateRangeMovementSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BalanceSummaryProvider>(
      builder: (context, provider, child) {
        if (provider.isLedgerLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final summary = provider.balanceSummary;
        return CustomerActivitySummary(
          netMovement: summary.netBalance,
          salesAmount: summary.creditAmount,
          salesCount: summary.creditCount,
          paymentsAmount: summary.paymentAmount,
          paymentsCount: summary.paymentCount,
        );
      },
    );
  }
}

/// The selected period's movement, rather than the current customer balance.
/// Kept independent of providers so the same presentation can be previewed.
class CustomerActivitySummary extends StatelessWidget {
  const CustomerActivitySummary({
    super.key,
    required this.netMovement,
    required this.salesAmount,
    required this.salesCount,
    required this.paymentsAmount,
    required this.paymentsCount,
  });

  final double netMovement;
  final double salesAmount;
  final int salesCount;
  final double paymentsAmount;
  final int paymentsCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: SpazaColors.border),
        borderRadius: BorderRadius.circular(SpazaRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Net movement',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              color: kSecondaryAccent,
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            label: 'Net movement ${CurrencyUtil.format(netMovement)}',
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                CurrencyUtil.format(netMovement),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: kTertiaryColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 280 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20;
              final sales = _MovementMetric(
                label: 'Sales',
                count: salesCount,
                amount: salesAmount,
                color: kTertiaryColor,
              );
              final payments = _MovementMetric(
                label: 'Payments',
                count: paymentsCount,
                amount: paymentsAmount,
                color: kPrimaryColor,
              );
              if (stack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [sales, const SizedBox(height: 12), payments],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: sales),
                  const SizedBox(width: 20),
                  Expanded(child: payments),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MovementMetric extends StatelessWidget {
  const _MovementMetric({
    required this.label,
    required this.count,
    required this.amount,
    required this.color,
  });

  final String label;
  final int count;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label · $count',
          style: theme.textTheme.bodySmall?.copyWith(color: kSecondaryAccent),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            CurrencyUtil.format(amount),
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
