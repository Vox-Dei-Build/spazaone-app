import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/responsive_app_layout.dart';

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
    final compactLandscape = usesCompactLandscapeLayout(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: compactLandscape ? 4 : 8),
        Material(
          key: const Key('marketing-command-card'),
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: .48,
          ),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compactLandscape ? 10 : 12,
              vertical: compactLandscape ? 7 : 10,
            ),
            child: Row(
              children: [
                Container(
                  width: compactLandscape ? 36 : 40,
                  height: compactLandscape ? 36 : 40,
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.campaign_outlined,
                    color: kPrimaryColor,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WhatsApp promotion',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: kTertiaryColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (!compactLandscape)
                        Text(
                          'Choose a product and customers',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: kSecondaryAccent,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('marketing-choose-product'),
                  onPressed: onChooseProduct,
                  style: FilledButton.styleFrom(
                    minimumSize: Size(
                      compactLandscape ? 94 : 104,
                      LayoutConstants.minTouchTarget,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create'),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: compactLandscape ? 6 : 10),
        Text(
          'Recent promotions',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: compactLandscape ? 2 : 6),
        Expanded(child: campaignHistory),
      ],
    );
  }
}
