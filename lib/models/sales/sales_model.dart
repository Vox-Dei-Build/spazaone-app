import 'package:cloud_firestore/cloud_firestore.dart';

class Sale {
  final String id;
  final double amount;
  final String type;
  final Map<String, int> products; // Product ID -> Qty
  final DateTime dateAdded;
  final String? remarks;

  Sale({
    required this.id,
    required this.amount,
    required this.type,
    required this.products,
    required this.dateAdded,
    this.remarks,
  });

  // ---- helpers ----
  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;

    // Handle range or object shapes, e.g. {start: x, end: y}
    if (v is Map) {
      final dynamic end = v['end'] ?? v['value'] ?? v['amount'];
      if (end is num) return end.toDouble();
      if (end is String) return double.tryParse(end) ?? 0.0;

      // last resort: pick first numeric in the map
      for (final e in v.values) {
        if (e is num) return e.toDouble();
        if (e is String) {
          final parsed = double.tryParse(e);
          if (parsed != null) return parsed;
        }
      }
    }
    return 0.0;
  }

  static DateTime _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d != null) return d;
    }
    throw FormatException('Unrecognized date format: $v');
  }

  static Map<String, int> _asProducts(dynamic v) {
    final out = <String, int>{};
    if (v is Map) {
      v.forEach((k, val) {
        if (k == null) return;
        if (val is num) {
          out['$k'] = val.toInt();
        } else if (val is String) {
          final parsed = int.tryParse(val);
          if (parsed != null) out['$k'] = parsed;
        }
      });
    }
    return out;
  }

  // ---- factory ----
  factory Sale.fromMap(Map<String, dynamic> data, String documentId) {
    return Sale(
      id: documentId,
      amount: _asDouble(data['amount']),
      type: (data['type'] ?? 'Unknown').toString(),
      products: _asProducts(data['products']),
      dateAdded: _asDate(data['dateAdded']),
      remarks: (data['remarks'] == null || data['remarks'] == '')
          ? null
          : data['remarks'].toString(),
    );
  }
}
