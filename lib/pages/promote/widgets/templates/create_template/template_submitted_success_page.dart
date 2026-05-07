import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';

/// Success / "what happens next" screen shown immediately after a merchant
/// submits a new WhatsApp template for approval.
///
/// Replaces the previous snackbar-and-pop flow which left users wondering
/// what just happened. This screen sets timing expectations honestly,
/// explains the notification channel they'll be notified through, and offers
/// two clear next actions.
class TemplateSubmittedSuccessPage extends StatelessWidget {
  /// The friendly name the merchant gave the template — so we can address
  /// it back to them in copy.
  final String displayName;

  /// Called when the merchant taps "View pending templates". Defaults to
  /// just popping back to wherever the page was shown from.
  final VoidCallback? onViewPending;

  /// Called when the merchant taps "Done". Defaults to popping the page.
  final VoidCallback? onDone;

  const TemplateSubmittedSuccessPage({
    super.key,
    required this.displayName,
    this.onViewPending,
    this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const CustomAppBar(title: 'Submitted'),
      body: Padding(
        padding: LayoutConstants.padding20Horizontal,
        child: Column(
          children: [
            SizedBox(height: SizeConfig.heightMultiplier * 4),
            // Hero icon ─────────────────────────────────────────────────
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.1),
              ),
              child: Icon(
                Icons.send_rounded,
                size: 44,
                color: theme.colorScheme.primary,
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 3),
            Text(
              'Template submitted!',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '"$displayName" is on its way to WhatsApp for review.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.disabledColor),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: SizeConfig.heightMultiplier * 4),

            // What happens next ────────────────────────────────────────
            _StepRow(
              number: 1,
              title: 'WhatsApp reviews it',
              body:
                  'Most templates are approved within a few minutes — sometimes it takes a few hours, occasionally up to 24 hours.',
            ),
            const _StepDivider(),
            _StepRow(
              number: 2,
              title: 'We send you a notification',
              body:
                  'You\'ll get a push notification the moment it\'s approved (or rejected with a reason). Tap it to jump straight back here.',
              icon: Icons.notifications_active_outlined,
            ),
            const _StepDivider(),
            _StepRow(
              number: 3,
              title: 'Run your first promotion',
              body:
                  'Once approved, the template will appear in the picker when you tap "Run Promotion".',
              icon: Icons.campaign_outlined,
            ),

            const Spacer(),

            // Actions ─────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onViewPending ?? () => Navigator.of(context).pop(),
                icon: const Icon(Icons.list_alt),
                label: const Text('View pending templates'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onDone ?? () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int number;
  final String title;
  final String body;
  final IconData? icon;

  const _StepRow({
    required this.number,
    required this.title,
    required this.body,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary.withOpacity(0.1),
          ),
          child: icon != null
              ? Icon(icon, size: 18, color: theme.colorScheme.primary)
              : Text(
                  '$number',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.disabledColor, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepDivider extends StatelessWidget {
  const _StepDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Container(
        width: 2,
        height: 16,
        color: Theme.of(context).dividerColor.withOpacity(0.4),
        margin: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }
}
