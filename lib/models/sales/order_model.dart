import 'package:pasella/utils/date_util.dart';

class OrderModel {
  final String id;
  final String status;
  final double total;
  final int itemsCount;
  final DateTime? createdAt;

  OrderModel({
    required this.id,
    required this.status,
    required this.total,
    required this.itemsCount,
    this.createdAt,
  });

  factory OrderModel.fromMap(Map<String, dynamic> data) {
    DateTime? createdAt;
    final rawDate = data['createdAt'];
    if (rawDate is Map<String, dynamic>) {
      createdAt = convertMapToDateTime(rawDate);
    } else if (rawDate is String) {
      createdAt = DateTime.tryParse(rawDate);
    }

    return OrderModel(
      id: data['id'] ?? '',
      status: data['status'] ?? 'pending',
      total: (data['total'] ?? data['amount'] ?? 0).toDouble(),
      itemsCount: data['itemsCount'] is int
          ? data['itemsCount']
          : int.tryParse(data['itemsCount']?.toString() ?? '') ?? 0,
      createdAt: createdAt,
    );
  }
}
