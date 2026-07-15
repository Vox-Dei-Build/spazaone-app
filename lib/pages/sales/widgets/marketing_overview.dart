import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';

/// The everyday Marketing surface.
///
/// Product promotion is intentionally presented as one small decision: choose
/// what to promote. SpazaOne owns message writing and channel routing after
/// that, while advanced template management stays out of the primary journey.
class MarketingOverview extends StatelessWidget {
  const MarketingOverview({
    super.key,
    required this.onChooseProduct,
    required this.campaignHistory,
  });

  final VoidCallback onChooseProduct;
  final Widget campaignHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: LayoutConstants.spaceMd),
        Container(
          padding: const EdgeInsets.all(LayoutConstants.spaceMd),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.13),
                theme.colorScheme.primary.withValues(alpha: 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(LayoutConstants.spaceSm),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.campaign_outlined,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: LayoutConstants.spaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Promote a product',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'No message writing or channel setup.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LayoutConstants.spaceMd),
              Text(
                'Choose a product and customers. SpazaOne writes the message, '
                'uses WhatsApp where available and automatically sends SMS to '
                'everyone else.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
              ),
              const SizedBox(height: LayoutConstants.spaceMd),
              const Wrap(
                spacing: LayoutConstants.spaceSm,
                runSpacing: LayoutConstants.spaceSm,
                children: [
                  _SimpleStep(number: '1', label: 'Choose product'),
                  _SimpleStep(number: '2', label: 'Pick customers'),
                  _SimpleStep(number: '3', label: 'Review & send'),
                ],
              ),
              const SizedBox(height: LayoutConstants.spaceMd),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: const Key('marketing-choose-product'),
                  onPressed: onChooseProduct,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Choose product'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: LayoutConstants.spaceLg),
        Row(
          children: [
            Icon(
              Icons.history,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: LayoutConstants.spaceSm),
            Text(
              'Campaign history',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: LayoutConstants.spaceSm),
        Expanded(child: campaignHistory),
      ],
    );
  }
}

class _SimpleStep extends StatelessWidget {
  const _SimpleStep({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LayoutConstants.spaceSm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            child: Text(
              number,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
