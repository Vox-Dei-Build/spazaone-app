import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

/// Shared presentation for money added, message costs and payout history.
class WalletActivityTile extends StatelessWidget {
  const WalletActivityTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.amountColor = SpazaColors.heading,
    this.status,
    this.onTap,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final String amount;
  final Color amountColor;
  final String? status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(builder: (context, constraints) {
            final stack = constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(16) > 22;
            final value = Text(amount,
                style:
                    theme.textTheme.titleSmall?.copyWith(color: amountColor));
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: SpazaColors.subtle,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: icon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                      if (stack) ...[const SizedBox(height: 8), value],
                      if (status != null) ...[
                        const SizedBox(height: 6),
                        Text(status!, style: theme.textTheme.labelLarge),
                      ],
                    ],
                  ),
                ),
                if (!stack) ...[const SizedBox(width: 12), value],
              ],
            );
          }),
        ),
      ),
    );
  }
}
