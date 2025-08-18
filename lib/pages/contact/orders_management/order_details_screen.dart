import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';

class OrderDetailScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String orderId;

  const OrderDetailScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.orderId,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _updated = false;

  // 🔥 New: action loading state
  bool _actionLoading = false;
  String?
      _busyAction; // 'ACCEPT_BNPL' | 'MARK_CASH_RECEIVED' | 'SETTLE_BNPL' | 'MARK_COLLECTED'

  DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is Map && v['_seconds'] is num) {
      final sec = (v['_seconds'] as num).toInt();
      final nanos = (v['_nanoseconds'] as num?)?.toInt() ?? 0;
      return DateTime.fromMillisecondsSinceEpoch(sec * 1000 + nanos ~/ 1000000);
    }
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  double _asNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  /// Live order stream from Firestore with light normalization
  Stream<Map<String, dynamic>> _orderStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const Stream.empty();

    final doc = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('sales')
        .doc(widget.orderId);

    return doc.snapshots().map((snap) {
      if (!snap.exists) return <String, dynamic>{};
      final s = snap.data() as Map<String, dynamic>;

      return {
        'type': s['type'] ?? '', // 👈 NEW
        'createdAt': s['dateAdded'] ?? s['createdAt'],
        'paidAt': s['paidAt'] ?? s['paymentDate'],
        'updatedAt': s['updatedAt'],
        'collectedAt': s['collectedAt'] ?? s['fulfilledAt'],
        'collected': s['collected'] == true,
        'paymentMethod': s['paymentMethod'] ?? '',
        'paymentStatus': s['paymentStatus'] ?? '',
        'status': (s['status'] ?? '').toString(),
        'subtotal': s['subtotal'] ?? s['subTotal'] ?? 0,
        'deliveryFee': s['deliveryFee'] ?? s['shipping'] ?? s['delivery'] ?? 0,
        'discount': s['discount'] ?? s['couponDiscount'] ?? 0,
        'total': s['amount'] ?? s['total'] ?? 0,
        'items': (s['items'] is List) ? s['items'] : const [],
      };
    });
  }

  Future<void> _callPayment(String action) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in.')),
      );
      return;
    }
    if (widget.orderId.isEmpty || action.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing order or action.')),
      );
      return;
    }

    debugPrint(
        '[updateOrderPayment] uid=$uid, orderId=${widget.orderId}, action=$action');

    setState(() {
      _actionLoading = true;
      _busyAction = action;
    });

    try {
      final fn = FirebaseFunctions.instance.httpsCallable('updateOrderPayment');
      await fn.call({
        'merchantId': uid,
        'orderId': widget.orderId,
        'paymentAction': action,
      });

      if (!mounted) return;
      setState(() => _updated = true);

      final labels = {
        'ACCEPT_BNPL': 'BNPL approved',
        'MARK_CASH_RECEIVED': 'Cash received',
        'MARK_COLLECTED': 'Marked as collected',
        'SETTLE_BNPL': 'Marked as paid',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(labels[action] ?? 'Updated')),
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[updateOrderPayment] code=${e.code} message=${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to update order')),
      );
    } catch (e) {
      debugPrint('[updateOrderPayment] unexpected error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unexpected error. Please try again.')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _actionLoading = false;
        _busyAction = null;
      });
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
      child: Scaffold(
        appBar: CustomAppBar(title: 'Order #${widget.orderId}'),
        body: Stack(
          children: [
            SafeArea(
              child: StreamBuilder<Map<String, dynamic>>(
                stream: _orderStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || (snapshot.data ?? {}).isEmpty) {
                    return const _ErrorEmpty(
                      title: 'Order not found',
                      subtitle: 'Please go back and try again.',
                      icon: Icons.error_outline,
                    );
                  }

                  final order = snapshot.data!;
                  final createdAtDt = _parseTs(order['createdAt']);
                  final updatedAtDt = _parseTs(order['updatedAt']);
                  final paidAtRaw = _parseTs(order['paidAt']);
                  final paymentMethod =
                      (order['paymentMethod'] ?? '').toString();
                  final paymentStatus =
                      (order['paymentStatus'] ?? '').toString();
                  final status =
                      (order['status'] ?? '').toString().toLowerCase();

                  final orderType = (order['type'] ?? '').toString();
                  final isBnpl = orderType.toUpperCase() == 'BNPL' ||
                      paymentMethod.toUpperCase() == 'BNPL' ||
                      status.contains('bnpl');
                  final isBnplApproved = isBnpl &&
                      (paymentStatus.toLowerCase() == 'approved' ||
                          status.contains('bnpl_outstanding'));

                  final isPaid = paymentStatus.toLowerCase() == 'paid' ||
                      status == 'paid' ||
                      status == 'fulfilled';

                  // paidAt lights up only if settled; BNPL approved but outstanding is not “paid”
                  final paidAtDt = isPaid ? (paidAtRaw ?? updatedAtDt) : null;

                  final isCollected = order['collected'] == true;
                  final collectedAtDt =
                      isCollected ? _parseTs(order['collectedAt']) : null;

                  final createdAt = createdAtDt != null
                      ? DateFormat('dd MMM yyyy · HH:mm').format(createdAtDt)
                      : '—';

                  final subtotal = _asNum(order['subtotal']);
                  final delivery = _asNum(order['deliveryFee']);
                  final discount = _asNum(order['discount']);
                  final total = _asNum(order['total']);

                  final List items = (order['items'] as List?) ?? const [];

                  return LayoutBuilder(
                    builder: (context, c) {
                      final horizontal = SizeConfig.imageSizeMultiplier * 5;
                      final vertical = SizeConfig.heightMultiplier * 2;

                      return CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.symmetric(
                                horizontal: horizontal, vertical: vertical),
                            sliver: SliverList.list(
                              children: [
                                _HeaderCard(
                                  customerName: widget.customerName,
                                  statusText: _statusLabel(
                                      status, isPaid, isCollected,
                                      isBnpl: isBnpl,
                                      isBnplApproved: isBnplApproved),
                                  statusColor: _statusColor(
                                      context, status, isPaid, isCollected,
                                      isBnpl: isBnpl,
                                      isBnplApproved: isBnplApproved),
                                  totalText: CurrencyUtil.format(total),
                                  dateText: createdAt,
                                  paymentMethod: paymentMethod.isEmpty
                                      ? (isBnpl ? 'BNPL' : '—')
                                      : paymentMethod,
                                  paymentStatus: paymentStatus.isEmpty
                                      ? (isBnplApproved
                                          ? 'approved'
                                          : (isBnpl ? 'pending' : '—'))
                                      : paymentStatus,
                                  orderId: widget.orderId,
                                ),
                                SizedBox(
                                    height: SizeConfig.heightMultiplier * 2),
                                _TimelineRow(
                                  createdAt: createdAtDt,
                                  paidAt: isPaid ? paidAtDt : null,
                                  collectedAt:
                                      isCollected ? collectedAtDt : null,
                                ),
                                SizedBox(
                                    height: SizeConfig.heightMultiplier * 2),
                                _Section(
                                  title: 'Amounts',
                                  child: _AmountsCard(
                                    subtotal: subtotal,
                                    delivery: delivery,
                                    discount: discount,
                                    total: total,
                                  ),
                                ),
                                SizedBox(
                                    height: SizeConfig.heightMultiplier * 2),
                                _ProductsSectionEnhanced(
                                  items: items,
                                  fallbackUserId:
                                      FirebaseAuth.instance.currentUser?.uid ??
                                          '',
                                ),
                                SizedBox(
                                    height: SizeConfig.heightMultiplier * 2),
                                _Section(
                                  title: 'Actions',
                                  child: _ActionsBlock(
                                    paymentMethod: paymentMethod,
                                    isPaid: isPaid,
                                    isCollected: isCollected,
                                    isBnpl: isBnpl,
                                    isBnplApproved: isBnplApproved,
                                    onAcceptBnpl: () =>
                                        _callPayment('ACCEPT_BNPL'),
                                    onMarkCash: () =>
                                        _callPayment('MARK_CASH_RECEIVED'),
                                    onSettleBnpl: () =>
                                        _callPayment('SETTLE_BNPL'),
                                    onMarkCollected: () =>
                                        _callPayment('MARK_COLLECTED'),
                                    busy: _actionLoading, // ✅ global busy flag
                                    busyAction:
                                        _busyAction, // ✅ which action is running
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),

            // 🔒 Global action overlay while any call is in progress
            if (_actionLoading) ...[
              const ModalBarrier(dismissible: false, color: Colors.black26),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status, bool isPaid, bool isCollected,
      {required bool isBnpl, required bool isBnplApproved}) {
    final s = status.toLowerCase();
    if (isCollected) return 'Collected';
    if (isPaid) return 'Paid';
    if (isBnpl) {
      if (isBnplApproved) return 'BNPL Outstanding';
      return 'BNPL Pending';
    }
    if (s.contains('cancel')) return 'Cancelled';
    if (s.contains('refund')) return 'Refunded';
    if (s.contains('fulfill')) return 'Fulfilled';
    if (s.contains('pending') || s.isEmpty) return 'Pending';
    return formatStringToCamelCase(s);
  }

  Color _statusColor(
      BuildContext c, String status, bool isPaid, bool isCollected,
      {required bool isBnpl, required bool isBnplApproved}) {
    final s = status.toLowerCase();
    if (isCollected) return Colors.blue;
    if (isPaid) return Colors.green;
    if (isBnpl) {
      return isBnplApproved
          ? Colors.deepOrange
          : Colors.orange; // outstanding vs pending
    }
    if (s.contains('cancel')) return Colors.red;
    if (s.contains('refund')) return Colors.purple;
    if (s.contains('fulfill')) return Colors.blue;
    if (s.contains('pending') || s.isEmpty) return Colors.amber;
    return Theme.of(c).colorScheme.primary;
  }
}

/// ---------- UI PIECES ----------

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.customerName,
    required this.statusText,
    required this.statusColor,
    required this.totalText,
    required this.dateText,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.orderId,
  });

  final String customerName;
  final String statusText;
  final Color statusColor;
  final String totalText;
  final String dateText;
  final String paymentMethod;
  final String paymentStatus;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    totalText,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: SizeConfig.textMultiplier * 2.6,
                    ),
                  ),
                ),
                _StatusPill(text: statusText, color: statusColor),
              ],
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 0.6),
            Text(
              'Order #$orderId • $dateText',
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.5,
                color: Colors.grey.shade700,
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1.2),
            Row(
              children: [
                _MetaChip(
                    icon: Icons.person,
                    label: formatStringToCamelCase(customerName)),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                _MetaChip(
                    icon: Icons.account_balance_wallet_outlined,
                    label: paymentMethod),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                _MetaChip(icon: Icons.verified_outlined, label: paymentStatus),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({this.createdAt, this.paidAt, this.collectedAt});
  final DateTime? createdAt;
  final DateTime? paidAt;
  final DateTime? collectedAt;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget dot(bool active) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade400,
            shape: BoxShape.circle,
          ),
        );
    Widget label(String text, DateTime? dt, bool active) => Column(
          children: [
            Text(text,
                style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            if (dt != null)
              Text(DateFormat('dd MMM • HH:mm').format(dt), style: t.bodySmall),
          ],
        );

    final createdActive = createdAt != null;
    final paidActive = paidAt != null;
    final collectedActive = collectedAt != null;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(children: [
              dot(createdActive),
              const SizedBox(height: 6),
              label('Created', createdAt, createdActive)
            ]),
            Expanded(
                child: Divider(
                    indent: 8,
                    endIndent: 8,
                    thickness: 2,
                    color: Colors.grey.shade300)),
            Column(children: [
              dot(paidActive),
              const SizedBox(height: 6),
              label('Paid', paidAt, paidActive)
            ]),
            Expanded(
                child: Divider(
                    indent: 8,
                    endIndent: 8,
                    thickness: 2,
                    color: Colors.grey.shade300)),
            Column(children: [
              dot(collectedActive),
              const SizedBox(height: 6),
              label('Collected', collectedAt, collectedActive)
            ]),
          ],
        ),
      ),
    );
  }
}

class _AmountsCard extends StatelessWidget {
  const _AmountsCard({
    required this.subtotal,
    required this.delivery,
    required this.discount,
    required this.total,
  });

  final double subtotal;
  final double delivery;
  final double discount;
  final double total;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    Widget row(String k, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  k,
                  style: TextStyle(
                    fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
                    fontSize: SizeConfig.textMultiplier * 1.7,
                  ),
                ),
              ),
              Text(
                v,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  fontSize: SizeConfig.textMultiplier * (bold ? 1.9 : 1.7),
                ),
              ),
            ],
          ),
        );

    final children = <Widget>[];
    if (subtotal > 0) {
      children.add(row('Subtotal', CurrencyUtil.format(subtotal)));
    }
    if (delivery > 0) {
      children.add(row('Delivery', CurrencyUtil.format(delivery)));
    }
    if (discount > 0) {
      children.add(row('Discount', '-${CurrencyUtil.format(discount)}'));
    }
    children.add(Divider(color: Colors.grey.shade300));
    children.add(row('Total', CurrencyUtil.format(total), bold: true));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }
}

class _ProductsSectionEnhanced extends StatelessWidget {
  const _ProductsSectionEnhanced(
      {required this.items, required this.fallbackUserId});
  final List items;
  final String fallbackUserId;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    if (items.isEmpty) {
      return _Section(
        title: 'Products',
        child: Text(
          'No products associated with this order.',
          style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.8),
        ),
      );
    }

    return _Section(
      title: 'Products',
      child: Column(
        children: items.map<Widget>((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final productId =
              (map['productId'] ?? map['id'] ?? map['productID'] ?? '')
                  .toString();
          final quantity = map['quantity'] ?? map['qty'] ?? 0;
          final lineTotal = (map['lineTotal'] ?? map['total'] ?? 0);
          final inlineName = (map['name'] ?? map['productName'])?.toString();
          final inlinePrice = map['price'] ?? map['sellingPrice'];

          if (productId.isEmpty) {
            return _ProductCardEnhanced(
              productName:
                  formatStringToCamelCase(inlineName ?? 'Unknown product'),
              quantity: quantity,
              unitPrice: inlinePrice is num ? inlinePrice.toDouble() : 0,
              imageUrl: null,
              lineTotal: lineTotal is num ? lineTotal.toDouble() : null,
            );
          }

          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(fallbackUserId)
                .collection('products')
                .doc(productId)
                .get(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                );
              }
              String? imageUrl;
              String name = inlineName ?? 'Unnamed product';
              double unitPrice = 0;

              if (snap.hasData && snap.data!.exists) {
                final data = snap.data!.data() as Map<String, dynamic>;
                name = (data['name'] ?? name).toString();
                name = formatStringToCamelCase(name);
                unitPrice = _num(data['sellingPrice'] ?? inlinePrice);
                final images = data['images'];
                if (data['imageUrl'] is String) {
                  imageUrl = data['imageUrl'];
                } else if (images is List &&
                    images.isNotEmpty &&
                    images.first is String) {
                  imageUrl = images.first as String;
                } else if (data['photoUrl'] is String) {
                  imageUrl = data['photoUrl'];
                } else if (data['thumbnail'] is String) {
                  imageUrl = data['thumbnail'];
                }
              } else {
                unitPrice = _num(inlinePrice);
              }

              return _ProductCardEnhanced(
                productName: name,
                quantity: quantity,
                unitPrice: unitPrice,
                imageUrl: imageUrl,
                lineTotal: lineTotal is num ? lineTotal.toDouble() : null,
              );
            },
          );
        }).toList(),
      ),
    );
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

class _ProductCardEnhanced extends StatelessWidget {
  const _ProductCardEnhanced({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.imageUrl,
    this.lineTotal,
  });

  final String productName;
  final dynamic quantity;
  final double unitPrice;
  final String? imageUrl;
  final double? lineTotal;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final qty =
        (quantity is num) ? quantity.toInt() : int.tryParse('$quantity') ?? 0;

    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 2.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Image + qty
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: SizeConfig.imageSizeMultiplier * 14,
                    height: SizeConfig.imageSizeMultiplier * 14,
                    color: Colors.grey.shade200,
                    child: imageUrl == null || imageUrl!.isEmpty
                        ? Icon(Icons.inventory_2,
                            size: SizeConfig.imageSizeMultiplier * 7,
                            color: Colors.grey.shade600)
                        : Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.broken_image,
                                color: Colors.grey.shade600),
                          ),
                  ),
                ),
                Positioned(
                  right: -2,
                  top: -2,
                  child: CircleAvatar(
                    radius: SizeConfig.imageSizeMultiplier * 3.8,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(
                      'x$qty',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: SizeConfig.textMultiplier * 1.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 3),
            // Texts
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: SizeConfig.textMultiplier * 1.9,
                    ),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 0.6),
                  Text(
                    'Unit: ${CurrencyUtil.format(unitPrice)}',
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.6,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
            if (lineTotal != null)
              Text(
                CurrencyUtil.format(lineTotal!),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: SizeConfig.textMultiplier * 1.9,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ⬇️ Replace your _ActionsBlock with this
class _ActionsBlock extends StatelessWidget {
  const _ActionsBlock({
    required this.paymentMethod,
    required this.isPaid,
    required this.isCollected,
    required this.isBnpl,
    required this.isBnplApproved,
    required this.onAcceptBnpl,
    required this.onMarkCash,
    required this.onSettleBnpl,
    required this.onMarkCollected,
    this.busy = false, // ✅ default
    this.busyAction, // ✅ which action is busy
  });

  final String paymentMethod;
  final bool isPaid;
  final bool isCollected;
  final bool isBnpl;
  final bool isBnplApproved;

  final VoidCallback onAcceptBnpl;
  final VoidCallback onMarkCash;
  final VoidCallback onSettleBnpl;
  final VoidCallback onMarkCollected;

  final bool busy;
  final String?
      busyAction; // 'ACCEPT_BNPL' | 'MARK_CASH_RECEIVED' | 'SETTLE_BNPL' | 'MARK_COLLECTED'

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    // BNPL requested but not yet approved
    if (!isPaid && isBnpl && !isBnplApproved) {
      buttons.add(_ActionBtn(
        label: 'Accept BNPL',
        icon: Icons.account_balance_wallet_outlined,
        onTap: onAcceptBnpl,
        busy: busy && busyAction == 'ACCEPT_BNPL', // ✅ per-button busy
      ));
    }

    // BNPL approved (outstanding), not yet paid
    if (!isPaid && isBnpl && isBnplApproved) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(height: 8));
      buttons.add(_ActionBtn(
        label: 'Mark as Paid (Settle BNPL)',
        icon: Icons.done_all_outlined,
        onTap: onSettleBnpl,
        busy: busy && busyAction == 'SETTLE_BNPL',
      ));
    }

    // Cash flow
    if (!isPaid && paymentMethod == 'Cash') {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(height: 8));
      buttons.add(_ActionBtn(
        label: 'Mark Cash Received',
        icon: Icons.payments_outlined,
        onTap: onMarkCash,
        busy: busy && busyAction == 'MARK_CASH_RECEIVED',
      ));
    }

    // Collection (optional: require payment first if you prefer)
    if (!isCollected) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(height: 8));
      buttons.add(_ActionBtn(
        label: 'Mark Collected',
        icon: Icons.inventory_2_outlined,
        onTap: onMarkCollected,
        busy: busy && busyAction == 'MARK_COLLECTED',
      ));
    }

    if (buttons.isEmpty) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('No further actions available.',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(children: buttons),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: SizeConfig.textMultiplier * 2.0),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ⬇️ Replace your _ActionBtn with this
class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false, // ✅ default
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: busy ? null : onTap, // ✅ disabled while busy
        icon: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              )
            : Icon(icon),
        label: Text(busy ? 'Working…' : label),
      ),
    );
  }
}

class _ErrorEmpty extends StatelessWidget {
  const _ErrorEmpty(
      {required this.title, required this.subtitle, required this.icon});
  final String title;
  final String subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: SizeConfig.imageSizeMultiplier * 12,
                color: Theme.of(context).colorScheme.primary),
            SizedBox(height: SizeConfig.heightMultiplier * 1.2),
            Text(title,
                style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2.2,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.7)),
          ],
        ),
      ),
    );
  }
}
