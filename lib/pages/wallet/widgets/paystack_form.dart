import 'package:flutter/material.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/widgets/payment_response_screen.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/paystack_service.dart'; // uses initializeTopUp(...)
import 'package:pasella/pages/wallet/widgets/paystack_webview.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';

class PaystackFormScreen extends StatefulWidget {
  const PaystackFormScreen({Key? key}) : super(key: key);

  @override
  State<PaystackFormScreen> createState() => _PaystackFormScreenState();
}

class _PaystackFormScreenState extends State<PaystackFormScreen> {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final String currentUserId = StoreSession.instance.storeId;
  bool isLoading = false;
  CampaignTopupChannel selectedChannel = CampaignTopupChannel.eft;

  String _money(int minor) => 'R ${(minor / 100).toStringAsFixed(2)}';

  @override
  void dispose() {
    amountController.dispose();
    emailController.dispose();
    super.dispose();
  }

  /// Start Paystack TOP-UP transaction (purpose = 'topup')
  Future<void> _startTransaction() async {
    final messenger = ScaffoldMessenger.of(context);

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
    final method = 'paystack_${selectedChannel.wireName}';
    await TelemetryService.instance.capture(
      WalletTopupStarted(amountBucket: amountBucket, method: method),
    );

    try {
      final quote = await PaystackService.quoteCampaignCreditV2(
        merchantId: currentUserId,
        creditAmountMinor: creditAmountMinor,
        channel: selectedChannel,
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm online top-up'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Campaign credits: ${_money(quote.creditAmountMinor)}'),
              const SizedBox(height: 8),
              Text('Paystack fee: ${_money(quote.providerFeeMinor)}'),
              const Divider(height: 24),
              Text(
                'Total to pay: ${_money(quote.totalChargeMinor)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Spaza One adds no collection fee. Your credits are added only after Paystack verifies the payment.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue to Paystack'),
            ),
          ],
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
        channel: selectedChannel,
        idempotencyKey:
            'topup:$currentUserId:${DateTime.now().microsecondsSinceEpoch}',
      );

      if (!mounted) return;
      setState(() => isLoading = false);

      // Open Paystack checkout
      final success = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => PaystackWebView(
            url: init.authorizationUrl,
            reference: init.reference, // ✅ use real reference from Paystack
            amount: amount,
          ),
        ),
      );

      // You can rely on the webhook to update the wallet;
      // this screen just shows the UX result.
      if (success == true) {
        await TelemetryService.instance.capture(
          WalletTopupCompleted(amountBucket: amountBucket, method: method),
        );
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentResponseScreen(
              isSuccess: true,
              message:
                  "Your payment was captured. Your balance will update shortly.",
              amount: amount,
              reference: init.reference,
            ),
          ),
        );
      } else {
        // success == null => user dismissed the WebView (back / close).
        // success == false => Paystack reported a failure.
        // Webhooks remain the source of truth for wallet credit; this event
        // tracks the UX outcome only.
        await TelemetryService.instance.capture(
          WalletTopupFailed(
            amountBucket: amountBucket,
            method: method,
            failureCode: success == null ? 'cancelled' : 'webview_failed',
          ),
        );
      }
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
                : 'Online top-up is temporarily unavailable. Please try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Top Up with Paystack'),
      body: Padding(
        padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomTextField(
              hintText: 'R100',
              prefixIcon: Icons.money_sharp,
              label: 'Enter Amount *',
              textInputType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              maxLength: 20,
              controller: amountController,
              validator: (value) => (value == null || value.isEmpty)
                  ? 'This field is required'
                  : null,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1.5),
            DropdownButtonFormField<CampaignTopupChannel>(
              value: selectedChannel,
              decoration: const InputDecoration(
                labelText: 'Payment method *',
                prefixIcon: Icon(Icons.account_balance_outlined),
                border: OutlineInputBorder(),
              ),
              items: CampaignTopupChannel.values
                  .map(
                    (channel) => DropdownMenuItem(
                      value: channel,
                      child: Text(channel.label),
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
            const SizedBox(height: 8),
            Text(
              'Card top-ups stay unavailable until Paystack can guarantee the exact local or international fee before checkout.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1.5),
            CustomTextField(
              hintText: 'user@example.com',
              prefixIcon: Icons.email_outlined,
              label: 'Enter Email *',
              textInputType: TextInputType.emailAddress,
              controller: emailController,
              validator: (value) => (value == null || value.isEmpty)
                  ? 'This field is required'
                  : null,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomButton(
                    onTap: isLoading
                        ? () => ()
                        : () {
                            _startTransaction(); // fire & forget
                          },
                    margin: const EdgeInsets.fromLTRB(10, 0, 10, 10.0),
                    title: 'Proceed to Paystack',
                  ),
                  if (isLoading)
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
