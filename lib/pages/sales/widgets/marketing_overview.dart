import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/constants/layout_constants.dart';

/// The everyday Marketing surface.
///
/// Merchants make one decision here: which product to promote. Message
/// writing and channel routing stay behind the scenes.
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
        Card(
          elevation: 0,
          color: theme.colorScheme.primaryContainer.withValues(alpha: .24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: .15),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(LayoutConstants.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.campaign_outlined,
                        color: kPrimaryColor,
                      ),
                    ),
                    const SizedBox(width: LayoutConstants.spaceMd),
                    Expanded(
                      child: Text(
                        'Promote a product',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LayoutConstants.spaceMd),
                FilledButton.icon(
                  key: const Key('marketing-choose-product'),
                  onPressed: onChooseProduct,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(
                      LayoutConstants.minTouchTarget,
                    ),
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.inventory_2_outlined, size: 20),
                  label: const Text('Choose a product'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: LayoutConstants.spaceLg),
        Text(
          'Campaigns',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: LayoutConstants.spaceSm),
        Expanded(child: campaignHistory),
      ],
    );
  }
}
