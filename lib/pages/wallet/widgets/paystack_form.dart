import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/pages/wallet/widgets/campaign_topup_verification_screen.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/campaign_topup_pending_store.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/paystack_service.dart';
import 'package:pasella/pages/wallet/widgets/paystack_webview.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';

class PaystackFormScreen extends StatefulWidget {
  const PaystackFormScreen({
    super.key,
    required this.allowedChannels,
    this.merchantId,
  });

  final List<String> allowedChannels;
  final String? merchantId;

  @override
  State<PaystackFormScreen> createState() => _PaystackFormScreenState();
}

class _PaystackFormScreenState extends State<PaystackFormScreen> {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  String get currentUserId =>
      widget.merchantId ?? StoreSession.instance.storeId;
  bool isLoading = false;
  CampaignTopupChannel? selectedChannel;

  List<CampaignTopupChannel> get _availableChannels {
    final allowed = widget.allowedChannels.toSet();
    final channels = CampaignTopupChannel.values
        .where((channel) => allowed.contains(channel.wireName))
        .toList(growable: false);
    return channels;
  }

  @override
  void initState() {
    super.initState();
    selectedChannel = _availableChannels.firstOrNull;
  }

  @override
  void dispose() {
    amountController.dispose();
    emailController.dispose();
    super.dispose();
  }

  /// Start Paystack TOP-UP transaction (purpose = 'topup')
  Future<void> _startTransaction() async {
    final messenger = ScaffoldMessenger.of(context);
    final channel = selectedChannel;

    if (channel == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Adding money is temporarily unavailable.'),
        ),
      );
      return;
    }

    if (amountController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Please enter email and amount")),
      );
      return;
    }

    late final int creditAmountMinor;
    try {
      creditAmountMinor =
          PaystackService.minorUnitsFromRandText(amountController.text);
    } on CampaignTopupException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      return;
    }
    final amount = creditAmountMinor / 100;

    if (currentUserId.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text("You must be signed in")),
      );
      return;
    }

    setState(() => isLoading = true);

    final amountBucket = amountBucketZAR(amount);
    final method = 'paystack_${channel.wireName}';
    await TelemetryService.instance.capture(
      WalletTopupStarted(amountBucket: amountBucket, method: method),
    );

    try {
      final quote = await PaystackService.quoteCampaignCreditV2(
        merchantId: currentUserId,
        creditAmountMinor: creditAmountMinor,
        channel: channel,
      );
      if (!mounted) return;
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => CampaignTopupConfirmationSheet(
          quote: quote,
          paymentMethod: channel.label,
        ),
      );
      if (confirmed != true) {
        if (mounted) setState(() => isLoading = false);
        return;
      }
      final init = await PaystackService.initializeCampaignCreditV2(
        merchantId: currentUserId,
        creditAmountMinor: creditAmountMinor,
        email: emailController.text.trim(),
        channel: channel,
        idempotencyKey:
            'topup:$currentUserId:${DateTime.now().microsecondsSinceEpoch}',
      );
      await CampaignTopupPendingStore.save(currentUserId, init.intentId!);

      if (!mounted) return;
      setState(() => isLoading = false);

      // A hosted-checkout return is only a navigation signal. Every outcome
      // enters the same server-owned verification flow.
      await Navigator.push<HostedCheckoutOutcome>(
        context,
        MaterialPageRoute(
          builder: (context) => PaystackWebView(
            url: init.authorizationUrl,
            reference: init.reference, // ✅ use real reference from Paystack
            amount: amount,
          ),
        ),
      );

      if (!mounted) return;
      final status = await Navigator.push<CampaignTopupStatus>(
        context,
        MaterialPageRoute(
          builder: (_) => CampaignTopupVerificationScreen(
            statusReader: () => PaystackService.campaignTopupStatusV2(
              merchantId: currentUserId,
              intentId: init.intentId!,
            ),
          ),
        ),
      );
      if (status != null && status != CampaignTopupStatus.checking) {
        await CampaignTopupPendingStore.clear(currentUserId);
      }
      if (status == CampaignTopupStatus.paid) {
        await TelemetryService.instance.capture(
          WalletTopupCompleted(amountBucket: amountBucket, method: method),
        );
      } else if (status != CampaignTopupStatus.checking) {
        await TelemetryService.instance.capture(
          WalletTopupFailed(
            amountBucket: amountBucket,
            method: method,
            failureCode: status?.name ?? 'verification_closed',
          ),
        );
      }
      if (!mounted) return;
      if (status == CampaignTopupStatus.checking) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'We are still checking your payment. Your balance will update only after confirmation.',
            ),
          ),
        );
      }
      Navigator.of(context).pop(status);
    } catch (e, st) {
      if (mounted) setState(() => isLoading = false);
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'paystack_form _startTransaction failed',
      );
      await TelemetryService.instance.capture(
        WalletTopupFailed(
          amountBucket: amountBucket,
          method: method,
          failureCode: 'exception',
        ),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is CampaignTopupException
                ? e.message
                : 'Adding money is temporarily unavailable. Please try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: const CustomAppBar(title: 'Add to SpazaOne balance'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight - 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Add money for customer messages and promotions.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    maxLength: 20,
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount to add *',
                      hintText: 'R100',
                      prefixIcon: Icon(Icons.money_sharp),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'This field is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  if (_availableChannels.isEmpty)
                    const DecoratedBox(
                      key: ValueKey('topup-channels-unavailable'),
                      decoration: BoxDecoration(
                        color: Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Adding money is temporarily unavailable.',
                        ),
                      ),
                    )
                  else
                    DropdownButtonFormField<CampaignTopupChannel>(
                      value: selectedChannel,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'How would you like to pay? *',
                        prefixIcon: Icon(Icons.account_balance_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: _availableChannels
                          .map(
                            (channel) => DropdownMenuItem(
                              value: channel,
                              child: Text(
                                channel.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: isLoading
                          ? null
                          : (channel) {
                              if (channel != null) {
                                setState(() => selectedChannel = channel);
                              }
                            },
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Receipt email *',
                      hintText: 'user@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'This field is required'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: isLoading || selectedChannel == null
                        ? null
                        : () => unawaited(_startTransaction()),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CampaignTopupConfirmationSheet extends StatelessWidget {
  const CampaignTopupConfirmationSheet({
    super.key,
    required this.quote,
    required this.paymentMethod,
  });

  final CampaignTopupQuote quote;
  final String paymentMethod;

  String _money(int minor) => 'R ${(minor / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Check payment details',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 20),
            _ReceiptRow(
              label: 'Amount added',
              value: _money(quote.creditAmountMinor),
            ),
            _ReceiptRow(label: 'Payment method', value: paymentMethod),
            _ReceiptRow(
              label: 'Payment fee',
              value: _money(quote.providerFeeMinor),
            ),
            const Divider(height: 28),
            _ReceiptRow(
              label: 'Total to pay',
              value: _money(quote.totalChargeMinor),
              strong: true,
            ),
            const SizedBox(height: 16),
            const Text(
              'We will add the money after your payment is confirmed.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Pay with ${paymentMethod.split(' ').first}'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = strong
        ? Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w800,
            )
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: style?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
