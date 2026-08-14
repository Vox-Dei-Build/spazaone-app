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
        Material(
          color: kHighLightColor,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(LayoutConstants.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_outlined,
                  color: kPrimaryColor,
                ),
                const SizedBox(height: LayoutConstants.spaceSm),
                Text(
                  'Send an offer on WhatsApp',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: kTertiaryColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: LayoutConstants.spaceSm),
                Text(
                  'Choose customers, add products and see the price before sending.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: kSecondaryAccent,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: LayoutConstants.spaceLg),
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
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Create promotion'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: LayoutConstants.spaceLg),
        Text(
          'Recent promotions',
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
