import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/models/commerce/commerce_order.dart';
import 'package:pasella/services/commerce_service.dart';
import 'package:pasella/utils/currency_util.dart';

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
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _OrderDetails(order: order),
        ),
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
    String? trackingCarrier,
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
      await CommerceService().updateOrder(
        orderId: order.id,
        action: action,
        trackingCarrier: trackingCarrier,
        trackingNumber: trackingNumber,
        trackingUrl: trackingUrl,
        supplierOrderId: supplierOrderId,
        reason: reason,
        refundReference: refundReference,
        refundNote: refundNote,
        manualPaymentNote: manualPaymentNote,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order updated.')),
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
      trackingCarrier: values['carrier'],
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
      title: 'CJ order placed',
      label: 'CJ order number',
      confirmLabel: 'Save and continue',
    );
    if (supplierOrderId == null) return;
    await _act(
      'submit_for_fulfilment',
      supplierOrderId: supplierOrderId,
    );
  }

  Future<void> _confirmManualPayment() async {
    final note = await _textDialog(
      context,
      title: 'Confirm payment received',
      label: 'Payment method or reference',
      confirmLabel: 'Confirm payment',
    );
    if (note == null) return;
    await _act('confirm_manual_payment', manualPaymentNote: note);
  }

  Future<void> _cancel() async {
    final reason = await _textDialog(
      context,
      title: 'Cancel order',
      label: 'Cancellation reason',
      confirmLabel: 'Cancel order',
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
                'cash' => 'Cash',
                'bnpl' => 'Pay later',
                final value => value,
              },
            ),
          _DetailRow(
              label: 'Supplier cost',
              value: CurrencyUtil.format(order.baseCostMinor / 100)),
          if (order.supplierProductCostMinor > 0)
            _DetailRow(
                label: 'CJ product',
                value:
                    CurrencyUtil.format(order.supplierProductCostMinor / 100)),
          if (order.supplierShippingCostMinor > 0)
            _DetailRow(
                label: 'CJ delivery',
                value:
                    CurrencyUtil.format(order.supplierShippingCostMinor / 100)),
          _DetailRow(
              label: 'Fee snapshot',
              value: CurrencyUtil.format(order.feeMinor / 100)),
          _DetailRow(
              label: 'Margin snapshot',
              value: CurrencyUtil.format(order.marginMinor / 100),
              highlight: true),
          if (order.supplierId == 'cj_dropshipping') ...[
            const Divider(height: 32),
            const Text('CJ fulfilment',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
                'Use these references when placing the supplier order in CJ.'),
            if (order.supplierSku.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText('SKU: ${order.supplierSku}'),
            ],
            if (order.supplierVariantId.isNotEmpty)
              SelectableText('Variant: ${order.supplierVariantId}'),
            if (order.supplierOrderId.isNotEmpty)
              SelectableText('CJ order: ${order.supplierOrderId}'),
            if (order.logisticName.isNotEmpty)
              Text('Delivery: ${order.logisticName}'
                  '${order.logisticAging.isEmpty ? '' : ' · ${order.logisticAging} days'}'),
          ],
          const Divider(height: 32),
          Text(order.buyerName,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(order.buyerPhone),
          const SizedBox(height: 8),
          Text(addressLines.join(', ')),
          if (order.trackingNumber?.isNotEmpty == true) ...[
            const Divider(height: 32),
            const Text('Tracking',
                style: TextStyle(fontWeight: FontWeight.w700)),
            Text([order.trackingCarrier, order.trackingNumber]
                .whereType<String>()
                .join(' · ')),
          ],
          const SizedBox(height: 24),
          ..._actions(),
        ],
      ),
    );
  }

  List<Widget> _actions() {
    final buttons = <Widget>[];
    void add(String label, IconData icon, VoidCallback onPressed,
        {bool destructive = false}) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(height: 10));
      buttons.add(
        destructive
            ? OutlinedButton.icon(
                onPressed: _working ? null : onPressed,
                icon: Icon(icon),
                label: Text(label),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              )
            : ElevatedButton.icon(
                onPressed: _working ? null : onPressed,
                icon: Icon(icon),
                label: Text(label),
              ),
      );
    }

    switch (order.status) {
      case 'pending_payment':
        if (order.paymentMethod == 'manual') {
          add('Confirm manual payment', Icons.payments_outlined,
              _confirmManualPayment);
        }
        add('Cancel order', Icons.cancel_outlined, _cancel, destructive: true);
      case 'paid':
        add(
            order.supplierId == 'cj_dropshipping'
                ? 'I ordered this from CJ'
                : 'Submit for fulfilment',
            Icons.outbox_outlined,
            _fulfill);
        add('Cancel and request refund', Icons.cancel_outlined, _cancel,
            destructive: true);
      case 'submitted_for_fulfilment':
        add('Mark shipped', Icons.local_shipping_outlined, _ship);
        add('Cancel and request refund', Icons.cancel_outlined, _cancel,
            destructive: true);
      case 'shipped':
        add('Mark delivered', Icons.check_circle_outline,
            () => _act('mark_delivered'));
      case 'cancelled':
        if (order.paymentStatus == 'refund_pending') {
          add('Confirm refund completed', Icons.currency_exchange, _refund);
        }
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
  final TextEditingController _carrier = TextEditingController();
  final TextEditingController _number = TextEditingController();
  final TextEditingController _url = TextEditingController();

  @override
  void dispose() {
    _carrier.dispose();
    _number.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Shipping details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: _carrier,
                  decoration: const InputDecoration(labelText: 'Carrier')),
              TextField(
                  controller: _number,
                  autofocus: true,
                  decoration:
                      const InputDecoration(labelText: 'Tracking number *')),
              TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                      labelText: 'Tracking link (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () {
              if (_number.text.trim().isEmpty) return;
              Navigator.pop(context, {
                'carrier': _carrier.text.trim(),
                'number': _number.text.trim(),
                'url': _url.text.trim(),
              });
            },
            child: const Text('Mark shipped'),
          ),
        ],
      );
}
