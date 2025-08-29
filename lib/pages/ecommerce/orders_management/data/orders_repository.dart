import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/models/sales/order_model.dart';

class OrdersRepository {
  final FirebaseAuth auth;
  final FirebaseFunctions functions;

  const OrdersRepository({required this.auth, required this.functions});

  Future<List<OrderModel>> fetchCustomerOrders({
    required String merchantId,
    required String customerId,
  }) async {
    final callable = functions.httpsCallable('getCustomerOrders');
    final result = await callable.call({
      'merchantId': merchantId,
      'customerId': customerId,
    });
    final List<dynamic> data = result.data['orders'] ?? [];
    return data
        .map((e) => OrderModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }
}
