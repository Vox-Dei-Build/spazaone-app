import 'package:cloud_firestore/cloud_firestore.dart';

class OrdersUnreadService {
  const OrdersUnreadService();

  Stream<int> stream(String userId) {
    if (userId.isEmpty) return const Stream<int>.empty();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data();
      final counts = data?['unreadCounts'];
      if (counts is Map && counts['orders'] is num) {
        return (counts['orders'] as num).toInt();
      }
      return (data?['ordersUnreadCount'] as num?)?.toInt() ?? 0;
    });
  }
}
