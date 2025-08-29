import 'package:cloud_firestore/cloud_firestore.dart';

class OrdersUnreadService {
  const OrdersUnreadService();

  Stream<int> stream(String userId) {
    if (userId.isEmpty) return const Stream<int>.empty();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((s) => (s.data()?['ordersUnreadCount'] as int?) ?? 0);
  }
}
