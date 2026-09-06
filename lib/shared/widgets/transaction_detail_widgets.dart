import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

enum TransactionDetailStatusTone { positive, attention, neutral }

/// Shared visual hierarchy for sale, payment and Pay Later detail screens.
class TransactionDetailHero extends StatelessWidget {
  const TransactionDetailHero({
    super.key,
    required this.eyebrow,
    required this.amount,
    required this.status,
    required this.meta,
    this.statusTone = TransactionDetailStatusTone.neutral,
  });

  final String eyebrow;
  final String amount;
  final String status;
  final String meta;
  final TransactionDetailStatusTone statusTone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (statusBackground, statusForeground) = switch (statusTone) {
      TransactionDetailStatusTone.positive => (
          SpazaColors.successSurface,
          SpazaColors.action
        ),
      TransactionDetailStatusTone.attention => (
          SpazaColors.accent,
          SpazaColors.ink
        ),
      TransactionDetailStatusTone.neutral => (
          SpazaColors.selected,
          SpazaColors.heading
        ),
    };

    return Semantics(
      container: true,
      label: '$eyebrow, $amount, $status, $meta',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(SpazaSpace.lg),
        decoration: BoxDecoration(
          color: SpazaColors.navy,
          borderRadius: BorderRadius.circular(SpazaRadius.surface),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    eyebrow.toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: SpazaColors.accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpazaSpace.sm,
                    vertical: SpazaSpace.xs,
                  ),
                  decoration: BoxDecoration(
                    color: statusBackground,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: statusForeground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpazaSpace.md),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                amount,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: SpazaSpace.sm),
            Text(
              meta,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: .78),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionDetailCard extends StatelessWidget {
  const TransactionDetailCard({
    super.key,
    this.title,
    required this.child,
  });

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(SpazaSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title case final value?) ...[
                Text(value, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: SpazaSpace.md),
              ],
              child,
            ],
          ),
        ),
      );
}

class TransactionDetailRow extends StatelessWidget {
  const TransactionDetailRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelWidget = Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(color: SpazaColors.muted),
    );
    final valueWidget = Text(
      value,
      textAlign: TextAlign.end,
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpazaSpace.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 260 ||
              MediaQuery.textScalerOf(context).scale(14) > 19;
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelWidget,
                const SizedBox(height: SpazaSpace.xs),
                Align(alignment: Alignment.centerLeft, child: valueWidget),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: labelWidget),
              const SizedBox(width: SpazaSpace.lg),
              Flexible(child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}
