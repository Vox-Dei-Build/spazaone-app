import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OrderRepository {
  OrderRepository._();

  static DateTime? parseTs(dynamic v) {
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

  static double asNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  /// Live order stream from Firestore with light normalization
  static Stream<Map<String, dynamic>> orderStream({required String orderId}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const Stream.empty();

    final doc = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('sales')
        .doc(orderId);

    return doc.snapshots().map((snap) {
      if (!snap.exists) return <String, dynamic>{};
      final s = snap.data() as Map<String, dynamic>;
      return {
        'type': s['type'] ?? '',
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
}
