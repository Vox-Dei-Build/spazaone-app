import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';

/// A concise first-run hand-off into the merchant's real workspace.
///
/// The previous paged walkthrough made the primary action move between
/// screens and could look broken when a system dialog or small phone changed
/// the available height. This single sheet keeps one clear starting action;
/// the full checklist remains available from My Store → Shop setup.
class MerchantOnboardingIntro extends StatelessWidget {
  const MerchantOnboardingIntro({
    super.key,
    required this.onOpenCustomers,
    required this.onOpenProducts,
  });

  final VoidCallback onOpenCustomers;

  /// Retained for source compatibility with existing callers. Product setup
  /// remains the second step in Shop Setup; first run deliberately starts
  /// with a customer so the sheet has one unambiguous primary action.
  final VoidCallback onOpenProducts;

  void _dismiss(
    BuildContext context, [
    MerchantOnboardingIntroAction? action,
  ]) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(action);
      return;
    }

    // Widget tests and any future inline render can mount this outside a
    // modal route. Preserve the existing callback contract in that case.
    switch (action) {
      case MerchantOnboardingIntroAction.openCustomers:
        onOpenCustomers();
      case MerchantOnboardingIntroAction.openProducts:
        onOpenProducts();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          LayoutConstants.spaceXl,
          LayoutConstants.spaceMd,
          LayoutConstants.spaceXl,
          LayoutConstants.spaceLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: LayoutConstants.spaceLg),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.storefront_outlined, color: primary, size: 28),
            ),
            const SizedBox(height: LayoutConstants.spaceLg),
            Text(
              'Welcome to Spaza One',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: LayoutConstants.spaceXs),
            Text(
              'Start with one customer. You can return to Shop setup from My Store.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: LayoutConstants.spaceLg),
            const _SetupStep(
              number: 1,
              icon: Icons.person_add_alt_1_outlined,
              title: 'Add a customer',
            ),
            const SizedBox(height: LayoutConstants.spaceSm),
            const _SetupStep(
              number: 2,
              icon: Icons.inventory_2_outlined,
              title: 'Add a product',
            ),
            const SizedBox(height: LayoutConstants.spaceXl),
            FilledButton.icon(
              onPressed: () => _dismiss(
                context,
                MerchantOnboardingIntroAction.openCustomers,
              ),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Add my first customer'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(
                  LayoutConstants.minTouchTarget,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: LayoutConstants.spaceXs),
            Center(
              child: TextButton(
                onPressed: () => _dismiss(context),
                child: const Text('I’ll do this later'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum MerchantOnboardingIntroAction { openCustomers, openProducts }

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.number,
    required this.icon,
    required this.title,
  });

  final int number;
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelLarge?.copyWith(
                color: primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(icon, size: 21, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
