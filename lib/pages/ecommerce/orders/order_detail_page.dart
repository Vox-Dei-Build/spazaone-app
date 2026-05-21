import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/actions_block.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/actions_dock.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/amounts_card.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/error_empty.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/header_card.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/products_section_enhanced.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/section.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/timeline_row.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/whatsapp_delivery_pill.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';
import 'package:pasella/services/order_status_messaging_service.dart';

import 'data/order_repository.dart';
import 'data/payment_service.dart';

class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.orderId,
  });

  final String customerId;
  final String customerName;
  final String orderId;

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage>
    with SingleTickerProviderStateMixin {
  bool _updated = false;
  bool _actionLoading = false;
  String? _busyAction;

  void _closePage() {
    Navigator.pop(context, _updated);
  }

  /// Guards `BnplOfferShown` so it fires once per page instance even though
  /// the StreamBuilder rebuilds on every Firestore snapshot.
  bool _bnplShownFired = false;

  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  ); // 2 tabs now

  Future<void> _callPayment(
    String action,
    Map<String, dynamic> order, {
    Map<String, dynamic> extraData = const {},
  }) async {
    setState(() {
      _actionLoading = true;
      _busyAction = action;
    });

    // 1) Server-side state transition. Pure data — no UI side-effects
    //    here so the caller can sequence post-action feedback against
    //    the messaging step that follows.
    final result = await PaymentService.updateOrderPayment(
      orderId: widget.orderId,
      action: action,
      extraData: extraData,
    );

    if (!mounted) return;

    if (!result.isSuccess) {
      // The server rejected the transition (or we never tried).
      // Surface the underlying reason verbatim so the merchant can act.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Failed to update order.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _actionLoading = false;
        _busyAction = null;
      });
      return;
    }

    // 2) The order itself is now in its new state. Tell the merchant
    //    *what just changed* — and, if a customer message is on the
    //    way, that the next step is in progress (not silent).
    final messenger = ScaffoldMessenger.of(context);
    if (result.sendIntent) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${result.stateLabel} · Notifying customer…'),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      messenger.showSnackBar(SnackBar(content: Text(result.stateLabel)));
    }

    // 3) Telemetry for the state change itself. Kept exactly as before
    //    so the analytics surface for BNPL accept/reject is unchanged.
    final amountBucket = amountBucketZAR(OrderRepository.asNum(order['total']));
    if (action == 'ACCEPT_BNPL') {
      await TelemetryService.instance.capture(
        BnplOfferAccepted(amountBucket: amountBucket, termDays: 0),
      );
    } else if (action == 'REJECT_BNPL') {
      await TelemetryService.instance.capture(
        BnplOfferRejected(amountBucket: amountBucket),
      );
    }

    // 4) Downstream WhatsApp + wallet debit. This used to be silent
    //    (PAS-UX-07 root cause): the merchant saw the optimistic
    //    "Cash received" snackbar above, then the wallet quietly
    //    dropped seconds later with no UI signal. We now await the
    //    explicit result and surface the final send/charge state on
    //    the same snackbar surface.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && result.sendIntent) {
      final msgSvc = await OrderStatusMessagingService.create();
      final driver = (order['driver'] is Map)
          ? Map<String, dynamic>.from(order['driver'] as Map)
          : <String, dynamic>{};
      final notif = await msgSvc.sendStatusMessage(
        action: action,
        merchantId: uid,
        customerId: widget.customerId,
        customerName: widget.customerName,
        orderId: widget.orderId,
        amount: CurrencyUtil.format(OrderRepository.asNum(order['total'])),
        itemsCount: ((order['items'] as List?)?.length ?? 0).toString(),
        pickupLocation: _fulfillmentSummary(order),
        driverName: (driver['name'] ?? '').toString(),
        driverPhone: (driver['phone'] ?? '').toString(),
      );

      if (!mounted) return;
      final finalSnack = _notificationSnackBar(result.stateLabel, notif);
      // Replace the "Notifying customer…" toast with the resolved
      // state. `clearSnackBars` keeps the most-recent-truth wins
      // semantics: merchants never see a stale interim message after
      // the final result is known.
      messenger
        ..clearSnackBars()
        ..showSnackBar(finalSnack);
    }

    if (!mounted) return;
    setState(() {
      _updated = true;
      _actionLoading = false;
      _busyAction = null;
    });
  }

  String _fulfillmentSummary(Map<String, dynamic> order) {
    final fulfillment = (order['fulfillmentType'] ?? '').toString();
    final time = (order['requestedFulfillmentTime'] ?? '').toString();
    final pickup = (order['pickupLabel'] ?? '').toString();
    final delivery = (order['deliveryAddress'] ?? order['deliveryInfo'] ?? '')
        .toString();
    final parts = <String>[
      if (fulfillment.isNotEmpty)
        fulfillment == 'delivery' ? 'Delivery' : 'Collection',
      if (time.isNotEmpty) time,
      if (fulfillment != 'delivery' && pickup.isNotEmpty) pickup,
      if (fulfillment == 'delivery' && delivery.isNotEmpty) delivery,
    ];
    return parts.isEmpty
        ? 'The shop will confirm collection or delivery.'
        : parts.join(', ');
  }

  Future<void> _assignDriver(
    Map<String, dynamic> order, {
    bool reassign = false,
  }) async {
    final driver = (order['driver'] is Map)
        ? Map<String, dynamic>.from(order['driver'] as Map)
        : <String, dynamic>{};
    final nameController = TextEditingController(
      text: reassign ? (driver['name'] ?? '').toString() : '',
    );
    final phoneController = TextEditingController(
      text: reassign ? (driver['phone'] ?? '').toString() : '',
    );
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(reassign ? 'Reassign driver' : 'Assign driver'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reassign)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Update the name or phone to switch driver. The customer '
                  'will get a fresh driver-assigned message.',
                ),
              ),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Driver name'),
              textInputAction: TextInputAction.next,
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Driver phone'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'driverName': nameController.text.trim(),
              'driverPhone': phoneController.text.trim(),
            }),
            child: Text(reassign ? 'Reassign' : 'Assign'),
          ),
        ],
      ),
    );
    nameController.dispose();
    phoneController.dispose();
    if (result == null) return;
    if ((result['driverName'] ?? '').isEmpty &&
        (result['driverPhone'] ?? '').isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a driver name or phone number.')),
      );
      return;
    }
    await _callPayment('ASSIGN_DRIVER', order, extraData: result);
  }

  Future<void> _confirmUnassignDriver(Map<String, dynamic> order) async {
    final driver = (order['driver'] is Map)
        ? Map<String, dynamic>.from(order['driver'] as Map)
        : <String, dynamic>{};
    final name = (driver['name'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unassign driver?'),
        content: Text(
          name.isEmpty
              ? 'This clears the driver from this order so you can assign '
                  'a different one. The customer is not notified.'
              : 'This removes $name from this order so you can assign a '
                  'different driver. The customer is not notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unassign'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _callPayment('UNASSIGN_DRIVER', order);
    }
  }

  Future<void> _confirmMarkOutForDelivery(Map<String, dynamic> order) async {
    final driver = (order['driver'] is Map)
        ? Map<String, dynamic>.from(order['driver'] as Map)
        : <String, dynamic>{};
    final name = (driver['name'] ?? '').toString();
    final phone = (driver['phone'] ?? '').toString();
    final summary = [
      if (name.isNotEmpty) name,
      if (phone.isNotEmpty) phone,
    ].join(' · ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mark out for delivery?'),
        content: Text(
          summary.isEmpty
              ? 'The customer will be told the order is on its way.'
              : 'Driver $summary is leaving the shop. The customer will be '
                  'told the order is on its way.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('On the way'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _callPayment('MARK_OUT_FOR_DELIVERY', order);
    }
  }

  Future<void> _confirmMarkDelivered(Map<String, dynamic> order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mark delivered?'),
        content: const Text(
          'This finalises the order. Stock will be deducted and the customer '
          'will receive a delivered confirmation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mark Delivered'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _callPayment('MARK_DELIVERED', order);
    }
  }

  Future<void> _launchExternal(Uri uri, String fallbackLabel) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $fallbackLabel.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $fallbackLabel.')),
      );
    }
  }

  Future<void> _callDriver(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return;
    await _launchExternal(Uri.parse('tel:$cleaned'), 'phone dialer');
  }

  Future<void> _whatsAppDriver(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return;
    final waNumber = cleaned.startsWith('+') ? cleaned.substring(1) : cleaned;
    await _launchExternal(
      Uri.parse('https://wa.me/$waNumber'),
      'WhatsApp',
    );
  }

  Future<void> _copyDriverPhone(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Driver phone copied.')),
    );
  }

  /// Builds the final snackbar shown after the customer-notification
  /// step settles. We always anchor the copy to the *new order state*
  /// (`stateLabel`) so the merchant sees both what the order is now
  /// and what happened to the wallet — never one without the other.
  SnackBar _notificationSnackBar(
    String stateLabel,
    OrderNotificationResult notif,
  ) {
    switch (notif.status) {
      case OrderNotificationStatus.sent:
        final priced = notif.cost > 0
            ? ' · ${CurrencyUtil.format(notif.cost)} charged'
            : '';
        return SnackBar(
          content: Text('$stateLabel · Customer notified$priced'),
          backgroundColor: Colors.green,
        );
      case OrderNotificationStatus.skippedNoPhone:
        return SnackBar(
          content: Text('$stateLabel · No phone on file — message not sent.'),
          backgroundColor: Colors.blueGrey,
        );
      case OrderNotificationStatus.skippedNoTemplate:
        return SnackBar(
          content: Text('$stateLabel · Template missing — message not sent.'),
          backgroundColor: Colors.blueGrey,
        );
      case OrderNotificationStatus.failed:
        return SnackBar(
          content: Text(
            '$stateLabel · Could not notify customer. Wallet not charged.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _updated);
        return false;
      },
      // We place the StreamBuilder OUTSIDE the Scaffold so the bottom bar
      // can access computed order fields.
      child: StreamBuilder<Map<String, dynamic>>(
        stream: OrderRepository.orderStream(orderId: widget.orderId),
        builder: (context, snapshot) {
          // Loading & empty states still need a Scaffold for AppBar/back
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return Scaffold(
              appBar: CustomAppBar(
                title: 'Order #${widget.orderId}',
                onBackPressed: _closePage,
              ),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          if (!snapshot.hasData || (snapshot.data ?? {}).isEmpty) {
            return Scaffold(
              appBar: CustomAppBar(
                title: 'Order #${widget.orderId}',
                onBackPressed: _closePage,
              ),
              body: const ErrorEmpty(
                title: 'Order not found',
                subtitle: 'Please go back and try again.',
                icon: Icons.error_outline,
              ),
            );
          }

          final order = snapshot.data!;

          final orderType = (order['type'] ?? '').toString();
          final paymentMethodTop = (order['paymentMethod'] ?? '').toString();

          final methodForLogic =
              ((paymentMethodTop.isNotEmpty ? paymentMethodTop : orderType))
                  .trim()
                  .toLowerCase();

          final methodForDisplay =
              paymentMethodTop.isNotEmpty ? paymentMethodTop : orderType;

          final createdAtDt = OrderRepository.parseTs(order['createdAt']);
          final updatedAtDt = OrderRepository.parseTs(order['updatedAt']);
          final paidAtRaw = OrderRepository.parseTs(order['paidAt']);
          final paymentMethod = (order['paymentMethod'] ?? '').toString();
          final paymentStatus = (order['paymentStatus'] ?? '').toString();
          final status = (order['status'] ?? '').toString().toLowerCase();

          final isBnpl = orderType.toUpperCase() == 'BNPL' ||
              methodForLogic == 'bnpl' ||
              status.contains('bnpl');

          final isBnplApproved = isBnpl &&
              (paymentStatus.toLowerCase() == 'approved' ||
                  status.contains('bnpl_outstanding'));
          final isBnplRejected = isBnpl &&
              (paymentStatus.toLowerCase() == 'rejected' ||
                  status.contains('bnpl_rejected'));

          final isPaid = paymentStatus.toLowerCase() == 'paid' ||
              status == 'paid' ||
              status == 'fulfilled';

          final paidAtDt = isPaid ? (paidAtRaw ?? updatedAtDt) : null;

          final isCollected = order['collected'] == true;
          final collectedAtDt = isCollected
              ? OrderRepository.parseTs(order['collectedAt'])
              : null;

          final isCancelled = status.contains('cancel');
          final isRejected = status.contains('reject') ||
              paymentStatus.toLowerCase() == 'rejected';
          final isTerminal = isCancelled || isRejected;
          final isPendingMerchantReview = status == 'pending_merchant_review';
          final isAcceptedOrder = status == 'accepted';
          final isOutForDelivery = status == 'out_for_delivery';
          final isDelivered = status == 'delivered';
          final isDelivery =
              (order['fulfillmentType'] ?? '').toString().toLowerCase() ==
                      'delivery' ||
                  (order['deliveryAddress'] ?? '').toString().isNotEmpty ||
                  (order['deliveryInfo'] ?? '').toString().isNotEmpty;
          final driver = (order['driver'] is Map)
              ? Map<String, dynamic>.from(order['driver'] as Map)
              : <String, dynamic>{};
          final hasDriver =
              (driver['name'] ?? '').toString().isNotEmpty ||
                  (driver['phone'] ?? '').toString().isNotEmpty ||
                  (driver['id'] ?? '').toString().isNotEmpty;
          final showAcceptReject =
              isPendingMerchantReview && !isCancelled && !isRejected;
          // Driver-allocation lifecycle:
          //  * Assign     — first allocation while order is queued for dispatch
          //  * Reassign   — same UI as assign, prefilled with current driver
          //  * Unassign   — corrective: clears the driver, walks back from
          //                 out_for_delivery to accepted on the server
          //  * OutForDelivery — driver has departed; only valid once a driver
          //                 is attached and the order isn't already delivered
          //  * Delivered  — terminal for delivery orders (parallel to
          //                 MARK_COLLECTED for pickup orders)
          final isInDriverAllocationWindow =
              (isAcceptedOrder || isOutForDelivery) && !isTerminal;
          final showAssignDriver =
              isAcceptedOrder && isDelivery && !hasDriver && !isTerminal;
          final showReassignDriver =
              isInDriverAllocationWindow && isDelivery && hasDriver;
          final showUnassignDriver =
              isInDriverAllocationWindow && isDelivery && hasDriver;
          final showMarkOutForDelivery = isAcceptedOrder &&
              isDelivery &&
              hasDriver &&
              !isTerminal;
          final showMarkDelivered =
              isOutForDelivery && isDelivery && !isDelivered && !isTerminal;
          // The legacy "Mark Collected" button stays for non-delivery
          // orders. We deliberately suppress it for delivery orders so
          // the merchant follows the explicit out-for-delivery → delivered
          // flow instead of skipping straight to "collected" — which
          // would mute the on-the-way customer ping.
          final showMarkCollected = !isCollected &&
              !isPendingMerchantReview &&
              !isDelivery &&
              !((methodForLogic == 'cash' ||
                      methodForLogic == 'transfer' ||
                      methodForLogic == 'eft') &&
                  !isPaid) &&
              !(isCancelled || isRejected);

          final createdAt = createdAtDt != null
              ? DateFormat('dd MMM yyyy · HH:mm').format(createdAtDt)
              : '—';
          final canMarkCash = (methodForLogic == 'cash' ||
                  methodForLogic == 'transfer' ||
                  methodForLogic == 'eft') &&
              !isPaid &&
              !isTerminal &&
              !isPendingMerchantReview;

          final subtotal = OrderRepository.asNum(order['subtotal']);
          final delivery = OrderRepository.asNum(order['deliveryFee']);
          final discount = OrderRepository.asNum(order['discount']);
          final total = OrderRepository.asNum(order['total']);
          final List items = (order['items'] as List?) ?? const [];
          final reviewRows = <MapEntry<String, String>>[
            if ((order['fulfillmentType'] ?? '').toString().isNotEmpty)
              MapEntry('Fulfillment', order['fulfillmentType'].toString()),
            if ((order['requestedFulfillmentTime'] ?? '').toString().isNotEmpty)
              MapEntry('Requested time',
                  order['requestedFulfillmentTime'].toString()),
            if ((order['deliveryAddress'] ?? '').toString().isNotEmpty)
              MapEntry('Delivery address', order['deliveryAddress'].toString()),
            if ((order['deliveryInfo'] ?? '').toString().isNotEmpty)
              MapEntry('Delivery note', order['deliveryInfo'].toString()),
            if (order['cashChangeFor'] != null)
              MapEntry('Cash change for', 'R${order['cashChangeFor']}'),
            if ((order['customerNote'] ?? '').toString().isNotEmpty)
              MapEntry('Customer note', order['customerNote'].toString()),
          ];

          // Fire BnplOfferShown once when the merchant first sees a pending
          // BNPL request. We defer to the next frame because we cannot fire
          // analytics events directly from inside a build method.
          if (isBnpl &&
              !isBnplApproved &&
              !isBnplRejected &&
              !_bnplShownFired) {
            _bnplShownFired = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              TelemetryService.instance.capture(
                BnplOfferShown(amountBucket: amountBucketZAR(total)),
              );
            });
          }

          final st = resolveOrderStatus(
            status: status,
            isPaid: isPaid,
            isCollected: isCollected,
            isBnpl: isBnpl,
            isBnplApproved: isBnplApproved,
            isBnplRejected: isBnplRejected,
            paymentMethod: paymentMethod,
            type: orderType,
            paymentStatus: paymentStatus,
          );

          // NEW:
          final payMeta = buildPaymentStatusMeta(
            context,
            paymentStatus: paymentStatus,
            paymentMethod: paymentMethod,
            type: orderType,
          );

          final pill = buildCollectionPill(
            isCollected: isCollected == true || isDelivered,
            isDelivery: isDelivery,
            isOutForDelivery: isOutForDelivery,
          );

          // PAS-AI-02: WhatsApp delivery state read off the order doc.
          final lastMessage = (order['lastMessage'] is Map)
              ? Map<String, dynamic>.from(order['lastMessage'] as Map)
              : <String, dynamic>{};
          final waState = WhatsAppDeliveryPill.fromMap(lastMessage);
          DateTime? waAt;
          String? waLabel;
          if (lastMessage.isNotEmpty) {
            final replied = OrderRepository.parseTs(lastMessage['repliedAt']);
            final delivered = OrderRepository.parseTs(
              lastMessage['deliveredAt'],
            );
            final failed = OrderRepository.parseTs(lastMessage['failedAt']);
            final sent = OrderRepository.parseTs(lastMessage['sentAt']);
            final queued = OrderRepository.parseTs(lastMessage['queuedAt']);
            if (replied != null) {
              waAt = replied;
              waLabel = 'Replied';
            } else if (delivered != null) {
              waAt = delivered;
              waLabel = 'Delivered';
            } else if (failed != null) {
              waAt = failed;
              waLabel = 'Failed';
            } else if (sent != null) {
              waAt = sent;
              waLabel = 'Sent';
            } else if (queued != null) {
              waAt = queued;
              waLabel = 'Queued';
            } else {
              waLabel = WhatsAppDeliveryPill.labelFor(
                waState,
              ).replaceFirst('WhatsApp · ', '');
              waLabel = waLabel[0].toUpperCase() + waLabel.substring(1);
            }
          }

          return Scaffold(
            appBar: CustomAppBar(
              title: 'Order #${widget.orderId}',
              onBackPressed: _closePage,
            ),
            bottomNavigationBar: ActionsDock(
              child: ActionsBlock(
                paymentMethod: methodForLogic,
                isPaid: isPaid,
                isBnpl: isBnpl,
                isBnplApproved: isBnplApproved,
                isCancelled: isCancelled,
                isRejected: isRejected,
                onAcceptOrder: () => _callPayment('ACCEPT_ORDER', order),
                onRejectOrder: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Reject order?'),
                      content: const Text(
                        'This will reject the WhatsApp order request.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Keep'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Reject'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) _callPayment('REJECT_ORDER', order);
                },
                onAssignDriver: () => _assignDriver(order),
                onReassignDriver: () =>
                    _assignDriver(order, reassign: true),
                onUnassignDriver: () => _confirmUnassignDriver(order),
                onMarkOutForDelivery: () =>
                    _confirmMarkOutForDelivery(order),
                onMarkDelivered: () => _confirmMarkDelivered(order),
                onAcceptBnpl: () => _callPayment('ACCEPT_BNPL', order),
                onRejectBnpl: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Reject BNPL?'),
                      content: const Text(
                        'This will decline the customer’s BNPL request.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Reject'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) _callPayment('REJECT_BNPL', order);
                },
                onMarkCash: () => _callPayment('MARK_CASH_RECEIVED', order),
                onSettleBnpl: () => _callPayment('SETTLE_BNPL', order),
                onMarkCollected: () => _callPayment('MARK_COLLECTED', order),
                onCancelOrder: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Cancel order?'),
                      content: const Text(
                        'This will cancel the order and release the cart.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Keep'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Cancel Order'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) _callPayment('CANCEL_ORDER', order);
                },
                showMarkCollected: showMarkCollected,
                showMarkCash: canMarkCash,
                showAcceptReject: showAcceptReject,
                showAssignDriver: showAssignDriver,
                showReassignDriver: showReassignDriver,
                showUnassignDriver: showUnassignDriver,
                showMarkOutForDelivery: showMarkOutForDelivery,
                showMarkDelivered: showMarkDelivered,
                isDelivery: isDelivery,
                busy: _actionLoading,
                busyAction: _busyAction,
                showEmptyMessage: false,
              ),
            ),
            body: Stack(
              children: [
                SafeArea(
                  child: Column(
                    children: [
                      TabBar(
                        controller: _tabController,
                        tabs: const [
                          Tab(text: 'Overview'),
                          Tab(text: 'Products'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // -------- Overview --------
                            LayoutBuilder(
                              builder: (context, c) {
                                final horizontal =
                                    SizeConfig.imageSizeMultiplier * 5;
                                final vertical =
                                    SizeConfig.heightMultiplier * 2;
                                return CustomScrollView(
                                  slivers: [
                                    SliverPadding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: horizontal,
                                        vertical: vertical,
                                      ),
                                      sliver: SliverList.list(
                                        children: [
                                          HeaderCard(
                                            customerName: widget.customerName,
                                            statusText: statusLabel(st),
                                            statusColor: statusColor(
                                              context,
                                              st,
                                            ),
                                            totalText: CurrencyUtil.format(
                                              total,
                                            ),
                                            dateText: createdAt,
                                            paymentMethod:
                                                methodForDisplay.isEmpty
                                                    ? (isBnpl ? 'BNPL' : '—')
                                                    : methodForDisplay,
                                            paymentStatus: paymentStatus.isEmpty
                                                ? (isBnplApproved
                                                    ? 'approved'
                                                    : (isBnpl
                                                        ? 'pending'
                                                        : '—'))
                                                : paymentStatus,
                                            orderId: widget.orderId,
                                            paymentStatusText: payMeta.label,
                                            paymentStatusColor: payMeta.color,
                                            collectionPill: pill,
                                            whatsAppState: waState,
                                          ),
                                          SizedBox(
                                            height:
                                                SizeConfig.heightMultiplier * 2,
                                          ),
                                          TimelineRow(
                                            createdAt: createdAtDt,
                                            paidAt: isPaid ? paidAtDt : null,
                                            collectedAt: isCollected
                                                ? collectedAtDt
                                                : null,
                                            whatsAppAt: waAt,
                                            whatsAppLabel: waLabel,
                                          ),
                                          SizedBox(
                                            height:
                                                SizeConfig.heightMultiplier * 2,
                                          ),
                                          if (isDelivery) ...[
                                            Section(
                                              title: 'Delivery',
                                              child: _DriverCard(
                                                hasDriver: hasDriver,
                                                driver: driver,
                                                isOutForDelivery:
                                                    isOutForDelivery,
                                                isDelivered: isDelivered,
                                                onCall: _callDriver,
                                                onWhatsApp: _whatsAppDriver,
                                                onCopy: _copyDriverPhone,
                                              ),
                                            ),
                                            SizedBox(
                                              height:
                                                  SizeConfig.heightMultiplier *
                                                      2,
                                            ),
                                          ],
                                          if (reviewRows.isNotEmpty) ...[
                                            Section(
                                              title: 'WhatsApp order',
                                              child: _ReviewDetailsCard(
                                                rows: reviewRows,
                                              ),
                                            ),
                                            SizedBox(
                                              height:
                                                  SizeConfig.heightMultiplier *
                                                      2,
                                            ),
                                          ],
                                          Section(
                                            title: 'Amounts',
                                            child: AmountsCard(
                                              subtotal: subtotal,
                                              delivery: delivery,
                                              discount: discount,
                                              total: total,
                                            ),
                                          ),
                                          const SizedBox(height: 24),
                                          // Add some bottom space so last content
                                          // doesn't sit flush against the docked panel
                                          const SizedBox(height: 64),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),

                            // -------- Products --------
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: SizeConfig.imageSizeMultiplier * 5,
                                vertical: SizeConfig.heightMultiplier * 2,
                              ),
                              child: ProductsSectionEnhanced(
                                items: items,
                                fallbackUserId:
                                    FirebaseAuth.instance.currentUser?.uid ??
                                        '',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_actionLoading) ...[
                  const ModalBarrier(dismissible: false, color: Colors.black26),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReviewDetailsCard extends StatelessWidget {
  const _ReviewDetailsCard({required this.rows});

  final List<MapEntry<String, String>> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows
              .map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.key,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(row.value),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

/// Compact delivery panel for the order detail page. Renders one of:
///   * "No driver yet" placeholder so the merchant always knows the
///     dispatch state of a delivery order
///   * The currently assigned driver, with tap-to-call / WhatsApp /
///     copy affordances and a fulfillment-stage chip
///
/// Lifted out of the inline review-rows so the driver row gets actual
/// real-estate (icons, status chip) and so a missing driver is visible
/// even when the order has no other WhatsApp metadata to display.
class _DriverCard extends StatelessWidget {
  const _DriverCard({
    required this.hasDriver,
    required this.driver,
    required this.isOutForDelivery,
    required this.isDelivered,
    required this.onCall,
    required this.onWhatsApp,
    required this.onCopy,
  });

  final bool hasDriver;
  final Map<String, dynamic> driver;
  final bool isOutForDelivery;
  final bool isDelivered;
  final ValueChanged<String> onCall;
  final ValueChanged<String> onWhatsApp;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (driver['name'] ?? '').toString();
    final phone = (driver['phone'] ?? '').toString();

    final stageChip = _stageChip(theme);

    if (!hasDriver) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                Icons.local_shipping_outlined,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No driver yet',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Use Assign Driver below to dispatch this delivery.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (stageChip != null) ...[
                const SizedBox(width: 8),
                stageChip,
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person_outline,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Driver' : name,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(phone, style: theme.textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
                if (stageChip != null) stageChip,
              ],
            ),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => onCall(phone),
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: const Text('Call'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onWhatsApp(phone),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                  TextButton.icon(
                    onPressed: () => onCopy(phone),
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Copy'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _stageChip(ThemeData theme) {
    if (isDelivered) {
      return _Chip(
        label: 'Delivered',
        color: Colors.teal,
        theme: theme,
      );
    }
    if (isOutForDelivery) {
      return _Chip(
        label: 'On the way',
        color: Colors.blue,
        theme: theme,
      );
    }
    if (hasDriver) {
      return _Chip(
        label: 'Awaiting dispatch',
        color: Colors.orange,
        theme: theme,
      );
    }
    return null;
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.theme,
  });
  final String label;
  final Color color;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
