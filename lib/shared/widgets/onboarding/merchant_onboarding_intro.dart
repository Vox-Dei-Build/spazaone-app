import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

/// One optional first step into the real workspace, with no required order.
/// The rest of the guide stays available in Settings → Shop setup.
class MerchantOnboardingIntro extends StatelessWidget {
  const MerchantOnboardingIntro({
    super.key,
    required this.onOpenCustomers,
    required this.onOpenProducts,
    this.onExplore,
  });

  final VoidCallback onOpenCustomers;
  final VoidCallback onOpenProducts;
  final VoidCallback? onExplore;

  void _dismiss(BuildContext context, [MerchantOnboardingIntroAction? action]) {
    // A sheet returns its choice so Dashboard can navigate after it closes.
    // Inline previews and pages use callbacks instead of popping their route.
    if (ModalRoute.of(context) is PopupRoute) {
      Navigator.of(context).pop(action);
      return;
    }
    switch (action) {
      case MerchantOnboardingIntroAction.openCustomers:
        onOpenCustomers();
      case MerchantOnboardingIntroAction.openProducts:
        onOpenProducts();
      case null:
        onExplore?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (ModalRoute.of(context) is PopupRoute) ...[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: SpazaColors.outline,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: SpazaColors.subtle,
                  borderRadius: BorderRadius.circular(SpazaRadius.control),
                ),
                child: const Icon(SpazaIcons.shop, color: SpazaColors.heading),
              ),
            ),
            const SizedBox(height: 20),
            Text('Welcome to Spaza One', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Start with what you need today. You can add the rest later.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: SpazaColors.muted),
            ),
            const SizedBox(height: 24),
            _FirstAction(
              icon: SpazaIcons.customers,
              title: 'Add a customer',
              description: 'Keep their details and balances together.',
              onTap: () => _dismiss(
                  context, MerchantOnboardingIntroAction.openCustomers),
            ),
            const SizedBox(height: 12),
            _FirstAction(
              icon: SpazaIcons.products,
              title: 'Add a product',
              description: 'Set a price and keep track of stock.',
              onTap: () =>
                  _dismiss(context, MerchantOnboardingIntroAction.openProducts),
            ),
            const SizedBox(height: 20),
            Text(
              'Find the full guide in Settings → Shop setup whenever you need it.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: SpazaColors.muted),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _dismiss(context),
              child: const Text('Explore the app'),
            ),
          ],
        ),
      ),
    );
  }
}

enum MerchantOnboardingIntroAction { openCustomers, openProducts }

class _FirstAction extends StatelessWidget {
  const _FirstAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: SpazaColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
        side: const BorderSide(color: SpazaColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: SpazaColors.muted),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(description,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: SpazaColors.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(SpazaIcons.next, size: 20, color: SpazaColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
