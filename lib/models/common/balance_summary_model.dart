import 'package:flutter/material.dart';

class BalanceSummary {
  final double netBalance;
  final int paymentCount;
  final double paymentAmount;
  final int creditCount;
  final double creditAmount;
  final int? totalCustomers;
  final int? owingNumberOfCustomers;
  final List<Widget>? children;

  BalanceSummary({
    required this.netBalance,
    required this.paymentCount,
    required this.paymentAmount,
    required this.creditCount,
    required this.creditAmount,
    this.totalCustomers,
    this.owingNumberOfCustomers,
    this.children,
  });

  bool equals(BalanceSummary other) {
    return netBalance == other.netBalance &&
        paymentCount == other.paymentCount &&
        paymentAmount == other.paymentAmount &&
        creditCount == other.creditCount &&
        creditAmount == other.creditAmount &&
        totalCustomers == other.totalCustomers &&
        owingNumberOfCustomers == other.owingNumberOfCustomers;
  }
}
