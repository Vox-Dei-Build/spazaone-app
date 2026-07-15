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
          clipBehavior: Clip.antiAlias,
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Column(
            children: [
              _CampaignHero(onChooseProduct: onChooseProduct),
              const _CampaignPath(),
            ],
          ),
        ),
        const SizedBox(height: LayoutConstants.spaceLg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your campaigns',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Review results or run one again.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.history_rounded,
              size: 22,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: LayoutConstants.spaceSm),
        Expanded(child: campaignHistory),
      ],
    );
  }
}

class _CampaignHero extends StatelessWidget {
  const _CampaignHero({required this.onChooseProduct});

  final VoidCallback onChooseProduct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        Positioned(
          right: -36,
          top: -48,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),
        ),
        Positioned(
          right: 54,
          bottom: -58,
          child: Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kSecondaryColor.withValues(alpha: 0.09),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(LayoutConstants.spaceLg),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF237F42), Color(0xFF105C30)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutConstants.spaceSm,
                  vertical: LayoutConstants.spaceXs,
                ),
                decoration: BoxDecoration(
                  color: kSecondaryColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'QUICK CAMPAIGN',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF29304F),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              const SizedBox(height: LayoutConstants.spaceMd),
              Text(
                'Choose what to promote',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: LayoutConstants.spaceSm),
              Text(
                'SpazaOne writes the message and automatically sends it on '
                'WhatsApp or SMS.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  height: 1.35,
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
                  backgroundColor: Colors.white,
                  foregroundColor: kPrimaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: const Icon(Icons.inventory_2_outlined, size: 20),
                label: const Text('Choose a product'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CampaignPath extends StatelessWidget {
  const _CampaignPath();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Three steps: choose a product, pick customers, review and send',
      child: Container(
        color: theme.colorScheme.surface,
        padding: const EdgeInsets.symmetric(
          horizontal: LayoutConstants.spaceMd,
          vertical: LayoutConstants.spaceMd,
        ),
        child: const Row(
          children: [
            Expanded(
              child: _PathStep(
                number: '1',
                icon: Icons.inventory_2_outlined,
                label: 'Product',
              ),
            ),
            _PathConnector(),
            Expanded(
              child: _PathStep(
                number: '2',
                icon: Icons.people_alt_outlined,
                label: 'Customers',
              ),
            ),
            _PathConnector(),
            Expanded(
              child: _PathStep(
                number: '3',
                icon: Icons.send_outlined,
                label: 'Send',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathStep extends StatelessWidget {
  const _PathStep({
    required this.number,
    required this.icon,
    required this.label,
  });

  final String number;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 19, color: kPrimaryColor),
            ),
            Positioned(
              right: -3,
              top: -3,
              child: CircleAvatar(
                radius: 8,
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
                child: Text(
                  number,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PathConnector extends StatelessWidget {
  const _PathConnector();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
