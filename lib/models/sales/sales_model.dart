import 'package:cloud_firestore/cloud_firestore.dart';

class Sale {
  final String id;
  final double amount;
  final String type;
  final Map<String, int> products; // Product ID and Quantity
  final DateTime dateAdded;
  final String? remarks;

  Sale(
      {required this.id,
      required this.amount,
      required this.type,
      required this.products,
      required this.dateAdded,
      this.remarks});

  factory Sale.fromMap(Map<String, dynamic> data, String documentId) {
    return Sale(
      id: documentId,
      amount: data['amount'] ?? 0.0,
      type: data['type'] ?? 'Unknown',
      products: Map<String, int>.from(data['products'] ?? {}),
      dateAdded: (data['dateAdded'] as Timestamp).toDate(),
      remarks: data['remarks'] ?? '',
    );
  }
}
