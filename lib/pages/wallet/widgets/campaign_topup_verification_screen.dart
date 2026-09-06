import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasella/services/paystack_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';

typedef CampaignTopupStatusReader = Future<CampaignTopupStatusResult>
    Function();

class CampaignTopupVerificationScreen extends StatefulWidget {
  const CampaignTopupVerificationScreen({
    super.key,
    required this.statusReader,
    this.pollDelays = const <Duration>[
      Duration.zero,
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 5),
      Duration(seconds: 8),
      Duration(seconds: 13),
      Duration(seconds: 20),
    ],
    this.successDelay = const Duration(seconds: 2),
  });

  final CampaignTopupStatusReader statusReader;
  final List<Duration> pollDelays;
  final Duration successDelay;

  @override
  State<CampaignTopupVerificationScreen> createState() =>
      _CampaignTopupVerificationScreenState();
}

class _CampaignTopupVerificationScreenState
    extends State<CampaignTopupVerificationScreen> with WidgetsBindingObserver {
  CampaignTopupStatus _status = CampaignTopupStatus.checking;
  int _creditAmountMinor = 0;
  bool _checking = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkUntilResolved());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_completed && !_checking) {
      unawaited(_checkUntilResolved());
    }
  }

  Future<void> _checkUntilResolved() async {
    if (_checking || _completed) return;
    _checking = true;
    try {
      for (final delay in widget.pollDelays) {
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (!mounted || _completed) return;
        try {
          final result = await widget.statusReader();
          if (!mounted) return;
          setState(() {
            _status = result.status;
            _creditAmountMinor = result.creditAmountMinor;
          });
          if (result.status == CampaignTopupStatus.paid) {
            _completed = true;
            await HapticFeedback.mediumImpact();
            if (!mounted) return;
            await Future<void>.delayed(widget.successDelay);
            if (mounted) Navigator.of(context).pop(CampaignTopupStatus.paid);
            return;
          }
          if (result.status != CampaignTopupStatus.checking) {
            _completed = true;
            return;
          }
        } catch (_) {
          // Network and short-lived backend failures remain a checking state.
          // The next bounded retry or app resume may safely recover.
        }
      }
      if (mounted && !_completed) {
        Navigator.of(context).pop(CampaignTopupStatus.checking);
      }
    } finally {
      _checking = false;
    }
  }

  String get _money => 'R ${(_creditAmountMinor / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final paid = _status == CampaignTopupStatus.paid;
    final checking = _status == CampaignTopupStatus.checking;
    final title = paid
        ? 'Money added'
        : checking
            ? 'Checking your payment'
            : _status == CampaignTopupStatus.needsReview
                ? 'Payment needs checking'
                : _status == CampaignTopupStatus.refundPending
                    ? 'Refund in progress'
                    : _status == CampaignTopupStatus.refunded
                        ? 'Payment refunded'
                        : 'Payment not completed';
    final message = paid
        ? '${_creditAmountMinor > 0 ? '$_money was' : 'Your money was'} added to your SpazaOne balance.'
        : checking
            ? 'This can take a moment. We will only update your balance after the payment is confirmed.'
            : _status == CampaignTopupStatus.needsReview
                ? 'We have not confirmed this payment yet. SpazaOne support can help check it.'
                : _status == CampaignTopupStatus.refundPending
                    ? 'Your refund is being confirmed. It is not complete yet.'
                    : _status == CampaignTopupStatus.refunded
                        ? 'The payment provider confirmed your refund.'
                        : 'No money was added to your SpazaOne balance.';

    return PopScope(
      canPop: !paid,
      child: Scaffold(
        appBar: const CustomAppBar(title: 'Payment status'),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Semantics(
                liveRegion: true,
                label: '$title. $message',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: paid
                          ? const Icon(
                              Icons.check_circle_rounded,
                              key: ValueKey('topup-paid'),
                              color: Colors.green,
                              size: 92,
                            )
                          : checking
                              ? const SizedBox(
                                  key: ValueKey('topup-checking'),
                                  width: 64,
                                  height: 64,
                                  child: CircularProgressIndicator(),
                                )
                              : Icon(
                                  _status == CampaignTopupStatus.refunded ||
                                          _status ==
                                              CampaignTopupStatus.refundPending
                                      ? Icons.replay_circle_filled_rounded
                                      : Icons.info_rounded,
                                  key: const ValueKey('topup-not-paid'),
                                  color: Colors.orange.shade800,
                                  size: 82,
                                ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            height: 1.4,
                          ),
                    ),
                    if (checking) ...[
                      const SizedBox(height: 28),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context)
                            .pop(CampaignTopupStatus.checking),
                        child: const Text('Back to balance'),
                      ),
                    ] else ...[
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(_status),
                        child: const Text('Back to balance'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
