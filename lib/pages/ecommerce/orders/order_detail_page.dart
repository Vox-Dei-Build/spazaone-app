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

  late final TabController _tabController =
      TabController(length: 2, vsync: this); // 2 tabs now

  Future<void> _callPayment(String action) async {
    setState(() {
      _actionLoading = true;
      _busyAction = action;
    });
    final ok = await PaymentService.updateOrderPayment(
      context: context,
      orderId: widget.orderId,
      action: action,
    );
    if (ok) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final msgSvc = await OrderStatusMessagingService.create();
        await msgSvc.sendStatusMessage(
          action: action,
          merchantId: uid,
          customerId: widget.customerId,
          customerName: widget.customerName,
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _updated = ok || _updated;
      _actionLoading = false;
      _busyAction = null;
    });
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
              appBar: CustomAppBar(title: 'Order #${widget.orderId}'),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          if (!snapshot.hasData || (snapshot.data ?? {}).isEmpty) {
            return Scaffold(
              appBar: CustomAppBar(title: 'Order #${widget.orderId}'),
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

          final createdAt = createdAtDt != null
              ? DateFormat('dd MMM yyyy · HH:mm').format(createdAtDt)
              : '—';

          final subtotal = OrderRepository.asNum(order['subtotal']);
          final delivery = OrderRepository.asNum(order['deliveryFee']);
          final discount = OrderRepository.asNum(order['discount']);
          final total = OrderRepository.asNum(order['total']);
          final List items = (order['items'] as List?) ?? const [];

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

          return Scaffold(
            appBar: CustomAppBar(title: 'Order #${widget.orderId}'),
            bottomNavigationBar: ActionsDock(
              child: ActionsBlock(
                paymentMethod: methodForLogic,
                isPaid: isPaid,
                isCollected: isCollected,
                isBnpl: isBnpl,
                isBnplApproved: isBnplApproved,
                onAcceptBnpl: () => _callPayment('ACCEPT_BNPL'),
                onRejectBnpl: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Reject BNPL?'),
                      content: const Text(
                          'This will decline the customer’s BNPL request.'),
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
                  if (ok == true) _callPayment('REJECT_BNPL');
                },
                onMarkCash: () => _callPayment('MARK_CASH_RECEIVED'),
                onSettleBnpl: () => _callPayment('SETTLE_BNPL'),
                onMarkCollected: () => _callPayment('MARK_COLLECTED'),
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
                                          vertical: vertical),
                                      sliver: SliverList.list(
                                        children: [
                                          HeaderCard(
                                            customerName: widget.customerName,
                                            statusText: statusLabel(st),
                                            statusColor:
                                                statusColor(context, st),
                                            totalText:
                                                CurrencyUtil.format(total),
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
