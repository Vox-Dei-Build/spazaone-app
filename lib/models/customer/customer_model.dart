import 'package:pasella/models/transactions/transaction_model.dart';

class Customer {
  final String id;
  final String name;
  final String number;
  final String category;
  final double balance;
  final Map<String, dynamic>? lastTransaction;
  final bool? isNPA;
  final String? profileImageUrl;

  Customer({
    required this.id,
    required this.name,
    required this.number,
    required this.category,
    required this.balance,
    this.lastTransaction,
    this.isNPA,
    this.profileImageUrl, // Initialize profile image URL
  });

  static Customer fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as String? ?? 'Unknown ID',
      name: map['name'] as String? ?? 'Unknown Name',
      number: map['number'] as String? ?? 'Unknown Number',
      category: map['category'] as String? ?? 'Unknown Category',
      lastTransaction: map['lastTransaction'] as Map<String, dynamic>?,
      balance: map['balance'] as double? ?? 0,
      isNPA: map['isNPA'] as bool? ?? false,
      profileImageUrl:
          map['profileImageUrl'] as String?, // Map profile image URL
    );
  }
}

class CustomerWithTransactions {
  final Customer customer;
  final List<LedgerTransaction> transactions;
  final int? unreadCount;

  CustomerWithTransactions({
    required this.customer,
    required this.transactions,
    this.unreadCount,
  });
}
