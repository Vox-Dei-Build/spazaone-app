import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/services/customer_payment_request_service.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/utils/show_toast.dart';

class CustomerPaymentRequestPanel extends StatefulWidget {
  const CustomerPaymentRequestPanel({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.mobileNumber,
    required this.isOwing,
    required this.onAddPhone,
    required this.onSetUpOnlinePayments,
    this.merchantId,
    this.service,
  });

  final String customerId;
  final String customerName;
  final String? mobileNumber;
  final bool isOwing;
  final FutureOr<void> Function() onAddPhone;
  final VoidCallback onSetUpOnlinePayments;
  final String? merchantId;
  final CustomerPaymentRequestGateway? service;

  @override
  State<CustomerPaymentRequestPanel> createState() =>
      _CustomerPaymentRequestPanelState();
}

class _CustomerPaymentRequestPanelState
    extends State<CustomerPaymentRequestPanel> {
  late final CustomerPaymentRequestGateway _service =
      widget.service ?? CustomerPaymentRequestService();
  CustomerPaymentRequestOverview? _overview;
  String? _error;
  bool _loading = false;
  bool _sending = false;
  String? _activeStatus;
  String? _idempotencyKey;

  @override
  void initState() {
    super.initState();
    if (_shouldLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void didUpdateWidget(covariant CustomerPaymentRequestPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.isOwing && widget.isOwing) ||
        oldWidget.customerId != widget.customerId ||
        oldWidget.mobileNumber != widget.mobileNumber) {
      _overview = null;
      _error = null;
      if (_shouldLoad) _load();
    }
  }

  bool get _shouldLoad =>
      FeatureFlags.enableCustomerPaymentRequests && widget.isOwing;

  Future<void> _load() async {
    if (_loading || !mounted || !_shouldLoad) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await _service.getOverview(
        merchantId: _merchantId,
        customerId: widget.customerId,
      );
      if (!mounted) return;
      setState(() => _overview = value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _merchantId {
    final supplied = widget.merchantId?.trim() ?? '';
    return supplied.isNotEmpty ? supplied : StoreSession.instance.storeId;
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    if (!_shouldLoad) return const SizedBox.shrink();
    final overview = _overview;
    final phoneMissing = overview?.reason == 'phone_missing' ||
        (overview == null && (widget.mobileNumber ?? '').trim().isEmpty);
    final retryable = _error != null ||
        {'pricing_unavailable', 'temporarily_unavailable'}
            .contains(overview?.reason);
    final statusText = _statusText(overview);

    return Padding(
      padding: EdgeInsets.only(top: SizeConfig.heightMultiplier * 1.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            key: const Key('customer-request-payment-button'),
            onPressed: _sending
                ? null
                : phoneMissing
                    ? _addPhoneAndRefresh
                    : overview?.canRequest == true
                        ? _confirmAndSend
                        : retryable
                            ? _load
                            : null,
            style: FilledButton.styleFrom(
              backgroundColor: phoneMissing
                  ? const Color(0xFFF3F4F6)
                  : const Color(0xFF168B3F),
              foregroundColor:
                  phoneMissing ? const Color(0xFF29295B) : Colors.white,
              disabledBackgroundColor: const Color(0xFFE5E7EB),
              disabledForegroundColor: const Color(0xFF6B7280),
              minimumSize: Size.fromHeight(
                SizeConfig.heightMultiplier * 5.8,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  SizeConfig.heightMultiplier * 1.4,
                ),
              ),
            ),
            icon: _sending || _loading
                ? SizedBox.square(
                    dimension: SizeConfig.imageSizeMultiplier * 4,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF29295B),
                    ),
                  )
                : Icon(
                    phoneMissing ? Icons.phone_outlined : Icons.send_rounded),
            label: Text(
              _buttonLabel(phoneMissing, overview),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (statusText != null) ...[
            SizedBox(height: SizeConfig.heightMultiplier * 0.7),
            Text(
              statusText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF6B7280),
                fontSize: SizeConfig.textMultiplier * 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addPhoneAndRefresh() async {
    await widget.onAddPhone();
    if (!mounted) return;
    setState(() {
      _overview = null;
      _error = null;
    });
    await _load();
  }

  String _buttonLabel(
    bool phoneMissing,
    CustomerPaymentRequestOverview? overview,
  ) {
    if (phoneMissing) return 'Add customer phone number';
    if (_sending) return 'Sending request…';
    if (_loading && overview == null) return 'Checking payment options…';
    if (_error != null) return 'Try again';
    if ({'pricing_unavailable', 'temporarily_unavailable'}
        .contains(overview?.reason)) {
      return 'Try again';
    }
    if (overview?.reason == 'cooldown_active') return 'Request sent';
    return 'Request payment';
  }

  String? _statusText(CustomerPaymentRequestOverview? overview) {
    if (_activeStatus == 'sent') return 'Payment request sent.';
    if (_activeStatus == 'needs_review') {
      return 'We could not confirm delivery. Support will review it.';
    }
    if (_activeStatus == 'failed' || _activeStatus == 'not_deliverable') {
      return 'Couldn’t send the request — try again.';
    }
    if (_sending) return 'We’re confirming that the message was accepted.';
    if (_error != null) return _error;
    if (overview?.reason == 'wallet_insufficient') {
      return 'Add money to your SpazaOne balance before sending.';
    }
    if (overview?.reason == 'temporarily_unavailable') {
      return 'Payment requests are temporarily unavailable.';
    }
    if (overview?.reason == 'pricing_unavailable') {
      return 'We can’t load the message price right now.';
    }
    final cooldown = overview?.cooldownEndsAtMs ?? 0;
    if (cooldown > DateTime.now().millisecondsSinceEpoch) {
      final when = DateTime.fromMillisecondsSinceEpoch(cooldown).toLocal();
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final whenDay = DateTime(when.year, when.month, when.day);
      if (whenDay == tomorrow) {
        return 'You can send another request tomorrow at ${DateFormat('HH:mm').format(when)}.';
      }
      return 'You can send another request on ${DateFormat('d MMM at HH:mm').format(when)}.';
    }
    final sentAt = overview?.lastRequest?.sentAtMs ?? 0;
    if (sentAt > 0) {
      final when = DateTime.fromMillisecondsSinceEpoch(sentAt).toLocal();
      final age = DateTime.now().difference(when);
      if (!age.isNegative && age.inMinutes < 60) {
        return 'Last request sent ${age.inMinutes.clamp(1, 59)} minutes ago.';
      }
      if (!age.isNegative && age.inHours < 24) {
        return 'Last request sent ${age.inHours} hours ago.';
      }
      return 'Last request sent ${DateFormat('d MMM at HH:mm').format(when)}.';
    }
    return null;
  }

  Future<void> _confirmAndSend() async {
    final overview = _overview;
    if (overview == null || !overview.canRequest) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _PaymentRequestConfirmationSheet(
        customerName: widget.customerName,
        overview: overview,
        onSetUpOnlinePayments: () {
          Navigator.pop(sheetContext, false);
          widget.onSetUpOnlinePayments();
        },
      ),
    );
    if (confirmed != true || !mounted) return;
    _idempotencyKey ??=
        'request_${widget.customerId}_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _sending = true;
      _activeStatus = 'queued';
    });
    try {
      final result = await _service.send(
        merchantId: _merchantId,
        customerId: widget.customerId,
        quoteKey: overview.quoteKey,
        pricingVersion: overview.pricingVersion,
        idempotencyKey: _idempotencyKey!,
      );
      await _poll(result.requestId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _activeStatus = 'failed';
        _idempotencyKey = null;
      });
      showSnackbar(context, error.toString(), Colors.red);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _poll(String requestId) async {
    const waits = <Duration>[
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 5),
    ];
    for (final wait in waits) {
      await Future<void>.delayed(wait);
      if (!mounted) return;
      final status = await _service.getStatus(requestId: requestId);
      setState(() => _activeStatus = status.status);
      if ({
        'sent',
        'failed',
        'not_deliverable',
        'needs_review',
        'customer_engaged',
        'link_created',
        'partially_paid',
        'paid',
      }.contains(status.status)) {
        _idempotencyKey = null;
        await _load();
        return;
      }
    }
    if (mounted) {
      setState(() => _activeStatus = 'queued');
      showSnackbar(
        context,
        'We’re still confirming delivery. You can leave this page.',
        Colors.blueGrey,
      );
    }
  }
}

class _PaymentRequestConfirmationSheet extends StatelessWidget {
  const _PaymentRequestConfirmationSheet({
    required this.customerName,
    required this.overview,
    required this.onSetUpOnlinePayments,
  });

  final String customerName;
  final CustomerPaymentRequestOverview overview;
  final VoidCallback onSetUpOnlinePayments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channel = overview.expectedChannel == 'whatsapp' ? 'WhatsApp' : 'SMS';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Send payment request?', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '$customerName will receive this by $channel.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 20),
            _RequestDetail(
              label: 'Amount owing',
              value: CurrencyUtil.format(overview.outstandingAmountMinor / 100),
            ),
            _RequestDetail(label: 'Delivery', value: channel),
            _RequestDetail(
              label: 'Message cost',
              value: CurrencyUtil.format(overview.messageCostMinor / 100),
            ),
            if (overview.expectedChannel == 'whatsapp' &&
                overview.fallbackMessageCostMinor != null)
              _RequestDetail(
                label: 'If WhatsApp cannot deliver',
                value:
                    '${CurrencyUtil.format(overview.fallbackMessageCostMinor! / 100)} by SMS',
              ),
            _RequestDetail(
              label: 'Balance after sending',
              value:
                  CurrencyUtil.format(overview.walletBalanceAfterMinor / 100),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7F6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(overview.messagePreview),
            ),
            const SizedBox(height: 12),
            Text(
              overview.onlinePaymentsReady
                  ? 'They can choose a full or partial secure payment in WhatsApp.'
                  : 'This sends a reminder only. No payment link will be included.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
              ),
            ),
            if (!overview.onlinePaymentsReady) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSetUpOnlinePayments,
                child: const Text('Set up online payments'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF168B3F),
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Send request'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestDetail extends StatelessWidget {
  const _RequestDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
