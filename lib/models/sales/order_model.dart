import 'package:cloud_firestore/cloud_firestore.dart';

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is int) return v != 0;
  if (v is String) {
    final t = v.trim().toLowerCase();
    return t == 'true' || t == '1' || t == 'yes';
  }
  return false;
}

DateTime? _asDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v);
  return null;
}

class OrderModel {
  final String id;
  final String status;
  final double total;
  final int? itemsCount;
  final DateTime? createdAt;

  final String? type;
  final String? paymentMethod;
  final String? paymentStatus;

  /// True when the function sends:
  /// - collected: true/1/"true"/"yes"
  /// - or isCollected: true
  /// - or collectedAt exists (Timestamp/String)
  final bool collected;

  OrderModel({
    required this.id,
    required this.status,
    required this.total,
    this.itemsCount,
    this.createdAt,
    this.type,
    this.paymentMethod,
    this.paymentStatus,
    this.collected = false,
  });

  factory OrderModel.fromMap(Map<String, dynamic> m) {
    final created = _asDate(m['createdAt']);
    final collectedAt = _asDate(m['collectedAt']);

    final rawCollected = m.containsKey('collected')
        ? _asBool(m['collected'])
        : m.containsKey('isCollected')
            ? _asBool(m['isCollected'])
            : false;

    final isCollected = rawCollected || (collectedAt != null);

    return OrderModel(
      id: m['id'] as String,
      status: (m['status'] ?? '') as String,
      total: (m['total'] ?? 0).toDouble(),
      itemsCount: (m['itemsCount'] as num?)?.toInt(),
      createdAt: created,
      type: m['type'] as String?,
      paymentMethod: m['paymentMethod'] as String?,
      paymentStatus: m['paymentStatus'] as String?,
      collected: isCollected,
    );
  }
}
