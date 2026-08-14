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

    final introduction = Material(
      key: const Key('marketing-command-card'),
      color: kSecondaryColor.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compactLandscape ? 12 : 16,
          vertical: compactLandscape ? 10 : 14,
        ),
        child: compactLandscape
            ? Row(
                children: [
                  const _PromotionIllustration(compact: true),
                  const SizedBox(width: 12),
                  Expanded(child: _PromotionCopy(theme: theme)),
                  const SizedBox(width: 12),
                  _ChooseProductButton(
                    onPressed: onChooseProduct,
                    compact: true,
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const _PromotionIllustration(),
                      const SizedBox(width: 13),
                      Expanded(child: _PromotionCopy(theme: theme)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ChooseProductButton(onPressed: onChooseProduct),
                ],
              ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: compactLandscape ? 4 : 8),
        introduction,
        SizedBox(height: compactLandscape ? 8 : 16),
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

class _PromotionIllustration extends StatelessWidget {
  const _PromotionIllustration({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 42.0 : 48.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kTertiaryColor.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(
        Icons.campaign_rounded,
        color: kTertiaryColor,
        size: 24,
      ),
    );
  }
}

class _PromotionCopy extends StatelessWidget {
  const _PromotionCopy({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Promote a product',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: kTertiaryColor,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Choose what to share with your customers on WhatsApp.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: kSecondaryAccent,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _ChooseProductButton extends StatelessWidget {
  const _ChooseProductButton({
    required this.onPressed,
    this.compact = false,
  });

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      key: const Key('marketing-choose-product'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: Size(
          compact ? 142 : double.infinity,
          LayoutConstants.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: const Icon(Icons.inventory_2_outlined, size: 18),
      label: const Text('Choose product'),
    );
  }
}
