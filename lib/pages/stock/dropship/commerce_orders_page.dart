import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pasella/models/commerce/commerce_order.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/commerce_service.dart';
import 'package:pasella/services/payment_receipt_tracker.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:url_launcher/url_launcher.dart';

const _earningStatuses = {
  'paid',
  'submitted_for_fulfilment',
  'shipped',
  'delivered',
};

class CommerceOrdersPage extends StatelessWidget {
  const CommerceOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CommerceOrder>>(
      stream: CommerceService().watchOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const _OrdersEmpty(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load dropship orders',
            message: 'Check your connection and try again.',
          );
        }
        final orders = snapshot.data ?? const [];
        if (orders.isEmpty) {
          return const _OrdersEmpty(
            icon: Icons.receipt_long_outlined,
            title: 'No dropship orders yet',
            message:
                'Order requests from your shared Spaza One links appear here.',
          );
        }
        final paidOrders = orders
            .where((order) => _earningStatuses.contains(order.status))
            .toList(growable: false);
        final revenue = paidOrders.fold<int>(
          0,
          (total, order) => total + order.amountDueMinor,
        );
        final margin = paidOrders.fold<int>(
          0,
          (total, order) => total + order.marginMinor,
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 100),
          children: [
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Paid revenue',
                    value: CurrencyUtil.format(revenue / 100),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Metric(
                    label: 'Snapshot margin',
                    value: CurrencyUtil.format(margin / 100),
                    highlight: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...orders.map(
              (order) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OrderCard(order: order),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> showCommerceOrderDetails(
  BuildContext context,
  CommerceOrder order,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _OrderDetails(order: order),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? Colors.green.shade50 : Colors.white,
        border: Border.all(
          color: highlight ? Colors.green.shade200 : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final CommerceOrder order;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showCommerceOrderDetails(context, order),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 62,
                  height: 62,
                  child: order.image.isEmpty
                      ? const ColoredBox(
                          color: Color(0xFFF0F3F2),
                          child: Icon(Icons.inventory_2_outlined),
                        )
                      : CachedNetworkImage(
                          imageUrl: order.image,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.productTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${order.buyerName} · ${_reference(order.id)}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 6),
                    _StatusChip(status: order.status),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyUtil.format(order.amountDueMinor / 100),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  if (_earningStatuses.contains(order.status))
                    Text(
                      '+${CurrencyUtil.format(order.marginMinor / 100)} margin',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 12,
                      ),
                    )
                  else if (order.paymentStatus == 'refund_pending')
                    Text(
                      'Refund pending',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else if (order.paymentStatus == 'refunded')
                    Text(
                      'Refunded',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderDetails extends StatefulWidget {
  const _OrderDetails({required this.order});

  final CommerceOrder order;

  @override
  State<_OrderDetails> createState() => _OrderDetailsState();
}

class _OrderDetailsState extends State<_OrderDetails> {
  bool _working = false;

  CommerceOrder get order => widget.order;

  Future<void> _act(
    String action, {
    String? trackingNumber,
    String? trackingUrl,
    String? supplierOrderId,
    String? reason,
    String? refundReference,
    String? refundNote,
    String? manualPaymentNote,
  }) async {
    setState(() => _working = true);
    try {
      final result = await CommerceService().updateOrder(
        orderId: order.id,
        action: action,
        trackingNumber: trackingNumber,
        trackingUrl: trackingUrl,
        supplierOrderId: supplierOrderId,
        reason: reason,
        refundReference: refundReference,
        refundNote: refundNote,
        manualPaymentNote: manualPaymentNote,
      );
      if (action == 'confirm_manual_payment') {
        await PaymentReceiptTracker.instance.capture(
          PaymentReceived(
            transactionId: 'commerce_order:${order.id}',
            amountBucket: amountBucketZAR(order.amountDueMinor / 100),
            source: 'commerce_order',
            method: 'manual',
          ),
        );
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(commerceOrderUpdateMessage(action, result))),
      );
    } catch (error) {
      if (mounted) showCommerceError(context, error);
      setState(() => _working = false);
    }
  }

  Future<void> _ship() async {
    final values = await _trackingDialog(context);
    if (values == null) return;
    await _act(
      'mark_shipped',
      trackingNumber: values['number'],
      trackingUrl: values['url'],
    );
  }

  Future<void> _fulfill() async {
    if (order.supplierId != 'cj_dropshipping') {
      await _act('submit_for_fulfilment');
      return;
    }
    final supplierOrderId = await _textDialog(
      context,
      title: 'Delivery order placed',
      label: 'Delivery order number',
      confirmLabel: 'Save and continue',
    );
    if (supplierOrderId == null) return;
    await _act(
      'submit_for_fulfilment',
      supplierOrderId: supplierOrderId,
    );
  }

  Future<void> _confirmManualPayment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm payment received?'),
        content: const Text(
          'Only continue after checking that the money reached you. '
          'The customer will be told that payment was received.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm and notify customer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _act(
      'confirm_manual_payment',
      manualPaymentNote: 'Merchant confirmed money received',
    );
  }

  Future<void> _cancel() async {
    final startsRefund = order.paymentStatus == 'paid';
    final reason = await _textDialog(
      context,
      title: startsRefund ? 'Cancel and start refund' : 'Cancel order',
      label: 'Reason for cancellation',
      confirmLabel: startsRefund ? 'Cancel and start refund' : 'Cancel order',
    );
    if (reason == null) return;
    await _act('cancel', reason: reason);
  }

  Future<void> _refund() async {
    final reference = await _textDialog(
      context,
      title: 'Confirm refund completed',
      label: 'Refund reference or note',
      confirmLabel: 'Record refund',
    );
    if (reference == null) return;
    await _act('mark_refunded', refundReference: reference);
  }

  @override
  Widget build(BuildContext context) {
    final address = order.deliveryAddress;
    final addressLines = [
      address['line1'],
      address['line2'],
      address['suburb'],
      address['city'],
      address['province'],
      address['postalCode'],
    ]
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order ${_reference(order.id)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _StatusChip(status: order.status),
            ],
          ),
          if (order.createdAt != null) ...[
            const SizedBox(height: 6),
            Text(DateFormat('dd MMM yyyy · HH:mm').format(order.createdAt!)),
          ],
          const Divider(height: 32),
          Text(order.productTitle,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          _DetailRow(
              label: order.paymentStatus == 'paid'
                  ? 'Payment confirmed'
                  : 'Order total',
              value: CurrencyUtil.format(order.amountDueMinor / 100)),
          if (order.buyerPaymentPreference.isNotEmpty)
            _DetailRow(
              label: 'Buyer selected',
              value: switch (order.buyerPaymentPreference) {
                'transfer' => 'EFT / deposit',
                'eft' => 'EFT / deposit',
                'cash' => 'Cash',
                'pay_at_shop' => 'Pay at shop',
                'bnpl' => 'Pay later',
                final value => value,
              },
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('Financial details'),
            children: [
              _DetailRow(
                  label: 'Delivery product cost',
                  value: CurrencyUtil.format(order.baseCostMinor / 100)),
              _DetailRow(
                  label: 'Spaza One fee',
                  value: CurrencyUtil.format(order.feeMinor / 100)),
              _DetailRow(
                  label: 'Your margin',
                  value: CurrencyUtil.format(order.marginMinor / 100),
                  highlight: true),
            ],
          ),
          if (order.supplierId == 'cj_dropshipping' &&
              order.status == 'paid') ...[
            const Divider(height: 32),
            const Text('Place delivery order',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Fulfilment partner: CJdropshipping'),
            const SizedBox(height: 4),
            const Text('Use these details to place the paid delivery order.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://www.cjdropshipping.com'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open fulfilment partner'),
            ),
            if (order.supplierSku.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText('SKU: ${order.supplierSku}'),
            ],
            if (order.supplierVariantId.isNotEmpty)
              SelectableText('Variant: ${order.supplierVariantId}'),
            if (order.supplierOrderId.isNotEmpty)
              SelectableText('Delivery order: ${order.supplierOrderId}'),
            if (order.logisticName.isNotEmpty)
              Text(
                'Delivery estimate: ${order.logisticAging.isEmpty ? 'Check when placing the order' : '${order.logisticAging} days'}',
              ),
          ] else if (order.supplierId == 'cj_dropshipping' &&
              order.supplierOrderId.isNotEmpty) ...[
            const Divider(height: 32),
            const Text(
              'Delivery order record',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            SelectableText('Delivery order: ${order.supplierOrderId}'),
          ],
          const Divider(height: 32),
          Text(order.buyerName,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(order.buyerPhone),
          const SizedBox(height: 8),
          Text(addressLines.join(', ')),
          if ((address['plusCode']?.toString() ?? '').isNotEmpty)
            SelectableText('Plus Code: ${address['plusCode']}'),
          if (order.status != 'pending_payment') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final details = [
                  order.buyerName,
                  order.buyerPhone,
                  addressLines.join(', '),
                  if ((address['plusCode']?.toString() ?? '').isNotEmpty)
                    'Plus Code: ${address['plusCode']}',
                  if (order.supplierSku.isNotEmpty) 'SKU: ${order.supplierSku}',
                  if (order.supplierVariantId.isNotEmpty)
                    'Variant: ${order.supplierVariantId}',
                ].join('\n');
                await Clipboard.setData(ClipboardData(text: details));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Order details copied.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Copy all order details'),
            ),
          ],
          if (order.trackingNumber?.isNotEmpty == true) ...[
            const Divider(height: 32),
            const Text('Tracking',
                style: TextStyle(fontWeight: FontWeight.w700)),
            SelectableText(order.trackingNumber ?? ''),
            if (order.trackingUrl?.isNotEmpty == true)
              SelectableText(order.trackingUrl!),
          ],
          const SizedBox(height: 24),
          ..._actions(),
        ],
      ),
    );
  }

  List<Widget> _actions() {
    final buttons = <Widget>[];
    void addPrimary(String label, IconData icon, VoidCallback onPressed) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: _working ? null : onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      );
    }

    final secondaryActions = <_OrderOverflowAction>[];

    switch (order.status) {
      case 'pending_payment':
        if (order.paymentMethod == 'manual') {
          addPrimary(
            'Confirm payment received & notify customer',
            Icons.payments_outlined,
            _confirmManualPayment,
          );
        }
        secondaryActions.add(_OrderOverflowAction.cancel);
      case 'paid':
        addPrimary(
          order.supplierId == 'cj_dropshipping'
              ? 'Place delivery order'
              : 'Submit for fulfilment',
          Icons.outbox_outlined,
          _fulfill,
        );
        secondaryActions.add(_OrderOverflowAction.cancel);
      case 'submitted_for_fulfilment':
        addPrimary('Add tracking', Icons.local_shipping_outlined, _ship);
        secondaryActions.add(_OrderOverflowAction.cancel);
      case 'shipped':
        addPrimary(
          'Mark delivered',
          Icons.check_circle_outline,
          () => _act('mark_delivered'),
        );
      case 'cancelled':
        if (order.paymentStatus == 'refund_pending') {
          secondaryActions.add(_OrderOverflowAction.refund);
        }
    }
    if (secondaryActions.isNotEmpty) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(height: 10));
      buttons.add(
        Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<_OrderOverflowAction>(
            key: const Key('commerce-order-more-actions'),
            enabled: !_working,
            tooltip: 'More order actions',
            onSelected: (action) {
              switch (action) {
                case _OrderOverflowAction.cancel:
                  _cancel();
                case _OrderOverflowAction.refund:
                  _refund();
              }
            },
            itemBuilder: (context) => [
              if (secondaryActions.contains(_OrderOverflowAction.cancel))
                PopupMenuItem(
                  value: _OrderOverflowAction.cancel,
                  child: Text(
                    order.paymentStatus == 'paid'
                        ? 'Cancel and start refund'
                        : 'Cancel order',
                  ),
                ),
              if (secondaryActions.contains(_OrderOverflowAction.refund))
                const PopupMenuItem(
                  value: _OrderOverflowAction.refund,
                  child: Text('Confirm refund completed'),
                ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.more_horiz),
                  SizedBox(width: 6),
                  Text('More order actions'),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_working) {
      buttons.insert(
          0,
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Center(child: CircularProgressIndicator()),
          ));
    }
    return buttons;
  }
}

enum _OrderOverflowAction { cancel, refund }

class _DetailRow extends StatelessWidget {
  const _DetailRow(
      {required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value,
              style: TextStyle(
                  fontWeight: highlight ? FontWeight.w800 : FontWeight.w500,
                  color: highlight ? Colors.green.shade700 : null)),
        ]),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(99)),
        child: Text(status.replaceAll('_', ' '),
            style: TextStyle(
                color: Colors.teal.shade800,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );
}

class _OrdersEmpty extends StatelessWidget {
  const _OrdersEmpty(
      {required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 58, color: Colors.grey),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ]),
        ),
      );
}

String _reference(String orderId) =>
    orderId.substring(0, orderId.length.clamp(0, 8)).toUpperCase();

bool isValidCommerceTrackingUrl(String value) {
  final text = value.trim();
  if (text.isEmpty) return true;
  final uri = Uri.tryParse(text);
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  return (scheme == 'https' || scheme == 'http') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

String commerceOrderUpdateMessage(
  String action,
  CommerceOrderUpdateResult result,
) {
  final saved = action == 'mark_shipped' ? 'Tracking saved' : 'Order updated';
  return switch (result.customerNotification) {
    'sent' => '$saved and customer notified.',
    'queued' => '$saved. Customer update is queued and will retry.',
    'not_deliverable' =>
      '$saved, but no customer number was available. Contact them directly.',
    'failed' =>
      '$saved, but the customer notification failed. Contact them directly.',
    'skipped' => '$saved.',
    _ => '$saved. Customer notification status is unavailable.',
  };
}

Future<String?> _textDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextInputDialog(
        title: title,
        label: label,
        confirmLabel: confirmLabel,
      ),
    );

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
  });

  final String title;
  final String label;
  final String confirmLabel;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () {
              final value = _controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: Text(widget.confirmLabel),
          ),
        ],
      );
}

Future<Map<String, String>?> _trackingDialog(BuildContext context) =>
    showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _TrackingInputDialog(),
    );

class _TrackingInputDialog extends StatefulWidget {
  const _TrackingInputDialog();

  @override
  State<_TrackingInputDialog> createState() => _TrackingInputDialogState();
}

class _TrackingInputDialogState extends State<_TrackingInputDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _number = TextEditingController();
  final TextEditingController _url = TextEditingController();

  @override
  void dispose() {
    _number.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add delivery tracking'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                    controller: _number,
                    autofocus: true,
                    decoration:
                        const InputDecoration(labelText: 'Tracking number *')),
                TextFormField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Tracking link (optional)',
                    hintText: 'https://tracking.example/123',
                    helperText: 'Use a secure https:// link when available.',
                  ),
                  validator: (value) => isValidCommerceTrackingUrl(value ?? '')
                      ? null
                      : 'Enter a valid http:// or https:// link.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () {
              if (_number.text.trim().isEmpty ||
                  !(_formKey.currentState?.validate() ?? false)) {
                return;
              }
              Navigator.pop(context, {
                'number': _number.text.trim(),
                'url': _url.text.trim(),
              });
            },
            child: const Text('Save and notify customer'),
          ),
        ],
      );
}
