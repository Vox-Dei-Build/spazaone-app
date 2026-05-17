import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  Future<void> _callPayment(String action, Map<String, dynamic> order) async {
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
      final notif = await msgSvc.sendStatusMessage(
        action: action,
        merchantId: uid,
        customerId: widget.customerId,
        customerName: widget.customerName,
        orderId: widget.orderId,
        amount: CurrencyUtil.format(OrderRepository.asNum(order['total'])),
        itemsCount: ((order['items'] as List?)?.length ?? 0).toString(),
        pickupLocation: (order['pickupLabel'] ?? '').toString(),
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
          final showMarkCollected = !isCollected &&
              !(methodForLogic == 'cash' && !isPaid) &&
              !(isCancelled || isRejected);

          final createdAt = createdAtDt != null
              ? DateFormat('dd MMM yyyy · HH:mm').format(createdAtDt)
              : '—';
          final isTerminal = isCancelled || isRejected;
          final canMarkCash =
              (methodForLogic == 'cash') && !isPaid && !isTerminal;

          final subtotal = OrderRepository.asNum(order['subtotal']);
          final delivery = OrderRepository.asNum(order['deliveryFee']);
          final discount = OrderRepository.asNum(order['discount']);
          final total = OrderRepository.asNum(order['total']);
          final List items = (order['items'] as List?) ?? const [];

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

          final pill = buildCollectionPill(isCollected: isCollected == true);

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
