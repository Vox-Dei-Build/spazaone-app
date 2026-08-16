import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/services/payment_setup_service.dart';
import 'package:pasella/utils/currency_util.dart';

String merchantSettlementStatusLabel(MerchantSettlement settlement) {
  if (settlement.testOnly) return 'Test only — not sent to bank';
  String date(int millis) => DateFormat('d MMM yyyy').format(
        DateTime.fromMillisecondsSinceEpoch(millis).toLocal(),
      );
  return switch (settlement.status.trim().toLowerCase()) {
    'paid' || 'completed' => settlement.providerSettlementAtMs > 0
        ? 'Paid · ${date(settlement.providerSettlementAtMs)}'
        : 'Paid',
    'pending' || 'processing' => settlement.expectedSettlementAtMs > 0
        ? 'Expected by ${date(settlement.expectedSettlementAtMs)}'
        : 'Processing',
    'failed' || 'review_required' => 'Needs attention',
    _ => 'Status unavailable',
  };
}

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

  String _money(int minor) => CurrencyUtil.format(minor / 100);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (hasError || overview == null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Online payment details are temporarily unavailable. Pull down to try again.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          )
        else ...[
          _OnlinePaymentSetupBlock(overview: overview!, onSetup: onSetup),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 22),
          Text(
            'Online sales payouts',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: kTertiaryColor,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
          if (overview!.outstandingSettlementMinor > 0 ||
              overview!.testOnlySettlementMinor > 0) ...[
            _PayoutTotals(overview: overview!),
            const SizedBox(height: 14),
          ],
          if (overview!.settlements.isEmpty)
            const _EmptyPayouts()
          else
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFE4E7E5)),
                ),
              ),
              child: Column(
                children: [
                  for (final payout in overview!.settlements)
                    _PayoutRow(
                      orderId: payout.orderId,
                      amount: _money(payout.merchantNetProceedsMinor),
                      status: merchantSettlementStatusLabel(payout),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _PayoutTotals extends StatelessWidget {
  const _PayoutTotals({required this.overview});

  final MerchantPaymentOverview overview;

  @override
  Widget build(BuildContext context) {
    String money(int value) => CurrencyUtil.format(value / 100);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kHighLightColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (overview.outstandingSettlementMinor > 0)
              _LineTotal(
                label: 'Outstanding payouts',
                value: money(overview.outstandingSettlementMinor),
              ),
            if (overview.testOnlySettlementMinor > 0) ...[
              if (overview.outstandingSettlementMinor > 0)
                const SizedBox(height: 8),
              _LineTotal(
                label: 'Test only',
                value: money(overview.testOnlySettlementMinor),
              ),
              const SizedBox(height: 4),
              const Text(
                'Test payments are not sent to your bank.',
                style: TextStyle(color: kSecondaryAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineTotal extends StatelessWidget {
  const _LineTotal({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      );
}

class _OnlinePaymentSetupBlock extends StatelessWidget {
  const _OnlinePaymentSetupBlock({required this.overview, this.onSetup});

  final MerchantPaymentOverview overview;
  final VoidCallback? onSetup;

  @override
  Widget build(BuildContext context) {
    final profile = overview.profile;
    final pending = profile.bankVerificationStatus == 'pending_review';
    final hasBank = profile.maskedAccount.isNotEmpty;
    final title = overview.enabled
        ? 'Ready for online sales'
        : pending
            ? 'We’re checking your bank details'
            : 'Get paid for online sales';
    final body = overview.enabled
        ? 'Customers can pay online and your share is sent to the bank account below.'
        : pending
            ? 'We’ll let you know when your bank account is ready.'
            : 'Add your bank account so customers can pay online and you can receive your money.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: kHighLightColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.account_balance_outlined,
              color: kPrimaryColor,
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: kTertiaryColor,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: kSecondaryAccent,
                height: 1.45,
              ),
        ),
        if (hasBank) ...[
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: kHighLightColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      color: kPrimaryColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${profile.bankName} · ${profile.maskedAccount}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (!overview.enabled && !pending && onSetup != null) ...[
          const SizedBox(height: 20),
          FilledButton(
            onPressed: onSetup,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Set up bank account'),
          ),
        ],
      ],
    );
  }
}

class _EmptyPayouts extends StatelessWidget {
  const _EmptyPayouts();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.receipt_long_outlined, color: kSecondaryAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No payouts yet',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Your payouts will appear here after you start receiving online payments.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: kSecondaryAccent,
                      height: 1.4,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({
    required this.orderId,
    required this.amount,
    required this.status,
  });

  final String orderId;
  final String amount;
  final String status;

  @override
  Widget build(BuildContext context) {
    final shortOrderId =
        orderId.substring(0, orderId.length < 8 ? orderId.length : 8);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.south_west_rounded, color: kPrimaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order $shortOrderId',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  status,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: kSecondaryAccent,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
