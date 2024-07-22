import 'package:cloud_firestore/cloud_firestore.dart';

class LedgerTransaction {
  final double amount;
  final String remarks;
  final String status;
  final String type;
  final DateTime date;
  final Map<String, int> products;

  LedgerTransaction({
    required this.amount,
    required this.remarks,
    required this.status,
    required this.type,
    required this.date,
    required this.products,
  });

  static LedgerTransaction fromMap(Map<String, dynamic> map) {
    return LedgerTransaction(
      amount: (map['amount'] is int)
          ? map['amount'].toDouble()
          : (map['amount'] as double?) ??
              0.0, // Defaulting to 0 if amount is null
      remarks: map['remarks'] as String? ??
          'No Remarks', // Default value if remarks are null
      status:
          map['status'] as String? ?? 'DUE', // Default value if status is null
      type: map['type'] as String? ?? 'Credit', // Default value if type is null
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      products: Map<String, int>.from(map['products'] ?? {}),
    );
  }
}
