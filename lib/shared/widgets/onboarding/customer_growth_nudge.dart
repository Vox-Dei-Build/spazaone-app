import 'package:flutter/material.dart';

class CustomerGrowthNudge extends StatelessWidget {
  static const int targetCustomers = 10;

  const CustomerGrowthNudge({
    super.key,
    required this.customerCount,
    this.onAddCustomer,
  });

  final int customerCount;
  final VoidCallback? onAddCustomer;

  @override
  Widget build(BuildContext context) {
    if (customerCount <= 0 || customerCount >= targetCustomers) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final progress = (customerCount / targetCustomers).clamp(0.0, 1.0);
    final remaining = targetCustomers - customerCount;
    final remainingLabel = remaining == 1 ? 'more customer' : 'more customers';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.groups_2_outlined,
                  color: primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Build toward 10 customers',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$customerCount of $targetCustomers saved '
                      'customers. Add $remaining $remainingLabel.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(
                          alpha: 0.75,
                        ),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: theme.colorScheme.surface,
              color: primary,
            ),
          ),
          if (onAddCustomer != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onAddCustomer,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Add Customer'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
