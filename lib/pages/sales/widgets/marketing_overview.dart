import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

/// One product promotion action followed by the existing campaign history.
/// The introduction scrolls away with history on short screens.
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
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverPadding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          sliver: SliverToBoxAdapter(
            child: Card(
              key: const Key('marketing-command-card'),
              margin: EdgeInsets.zero,
              elevation: 0,
              color: theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SpazaRadius.surface),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(builder: (context, constraints) {
                  final copy = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Promote a product',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Choose what to share with your customers on WhatsApp.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                  final action = FilledButton.icon(
                    key: const Key('marketing-choose-product'),
                    onPressed: onChooseProduct,
                    icon: const Icon(SpazaIcons.products, size: 20),
                    label: const Text('Choose product',
                        textAlign: TextAlign.center),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  );
                  if (constraints.maxWidth >= 600 &&
                      MediaQuery.textScalerOf(context).scale(14) <= 20) {
                    return Row(
                      children: [
                        Expanded(child: copy),
                        const SizedBox(width: 16),
                        action,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [copy, const SizedBox(height: 12), action],
                  );
                }),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child:
                Text('Recent promotions', style: theme.textTheme.titleMedium),
          ),
        ),
      ],
      body: campaignHistory,
    );
  }
}
