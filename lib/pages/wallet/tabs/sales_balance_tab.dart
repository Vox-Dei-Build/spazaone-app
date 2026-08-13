import 'package:flutter/material.dart';
import 'package:pasella/services/payment_setup_service.dart';

class MoneyPayoutsSection extends StatelessWidget {
  const MoneyPayoutsSection({
    super.key,
    required this.overview,
    this.loading = false,
    this.hasError = false,
    this.onSetup,
  });

  final MerchantPaymentOverview? overview;
  final bool loading;
  final bool hasError;
  final VoidCallback? onSetup;

  String _money(int minor) => 'R ${(minor / 100).toStringAsFixed(2)}';

  String _status(String raw) => switch (raw) {
        'paid' || 'completed' => 'Paid',
        'pending' || 'processing' => 'On the way',
        'failed' || 'review_required' => 'Needs attention',
        _ => raw.replaceAll('_', ' '),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Online sales payouts',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        if (loading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (hasError || overview == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Payout information is temporarily unavailable. Your sales records are unchanged.',
              ),
            ),
          )
        else ...[
          _PayoutBankCard(overview: overview!, onSetup: onSetup),
          const SizedBox(height: 18),
          Text(
            'Recent payouts',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (overview!.settlements.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No online sales payouts yet.'),
              ),
            )
          else
            for (final payout in overview!.settlements)
              Card(
                child: ListTile(
                  title: Text(
                    'Order ${payout.orderId.substring(0, payout.orderId.length < 8 ? payout.orderId.length : 8)}',
                  ),
                  subtitle: const Text('Money from an online sale'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _money(payout.merchantNetProceedsMinor),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(_status(payout.status)),
                    ],
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

class _PayoutBankCard extends StatelessWidget {
  const _PayoutBankCard({required this.overview, this.onSetup});

  final MerchantPaymentOverview overview;
  final VoidCallback? onSetup;

  @override
  Widget build(BuildContext context) {
    final profile = overview.profile;
    final pending = profile.bankVerificationStatus == 'pending_review';
    final hasBank = profile.maskedAccount.isNotEmpty;
    final body = overview.enabled
        ? 'Online payments are on.'
        : pending
            ? 'We are checking your bank details.'
            : 'Set up your bank account to accept online payments.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bank account for online sales',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (hasBank) ...[
              const SizedBox(height: 8),
              Text('${profile.bankName} · ${profile.maskedAccount}'),
            ],
            const SizedBox(height: 8),
            Text(body),
            if (!overview.enabled && !pending && onSetup != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onSetup,
                child: const Text('Set up bank account'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
