import 'package:flutter/material.dart';
import 'package:pasella/models/common/balance_summary_model.dart';
import 'package:pasella/pages/contact/widgets/action_buttons.dart';
import 'package:pasella/utils/transaction_util.dart';

class CustomerBalanceSummaryProvider with ChangeNotifier {
  String _customerName = '';
  String _customerId = '';
  String _mobileNumber = '';
  BalanceSummary _customerBalanceSummary = BalanceSummary(
      netBalance: 0.0,
      paymentCount: 0,
      paymentAmount: 0.0,
      creditCount: 0,
      creditAmount: 0.0,
      children: []);

  BalanceSummary get customerBalanceSummary => _customerBalanceSummary;

  void setCustomerDetails(String name, String id, String? mobileNumber) {
    _customerName = name;
    _customerId = id;
    _mobileNumber = mobileNumber != null ? mobileNumber : '';

    // Update the balance summary with new customer details
    _customerBalanceSummary = BalanceSummary(
      netBalance: _customerBalanceSummary.netBalance,
      paymentCount: _customerBalanceSummary.paymentCount,
      paymentAmount: _customerBalanceSummary.paymentAmount,
      creditCount: _customerBalanceSummary.creditCount,
      creditAmount: _customerBalanceSummary.creditAmount,
      totalCustomers: _customerBalanceSummary.totalCustomers,
      owingNumberOfCustomers: _customerBalanceSummary.owingNumberOfCustomers,
      children: [
        SizedBox(height: 15.0),
        AddCreditPaymentButtons(
          customerName: _customerName,
          customerId: _customerId,
          mobileNumber: _mobileNumber,
        ),
      ],
    );
  }

  void updateForCustomer(List<Map<String, dynamic>> transactions) {
    double netBalance = 0.0;
    TransactionStats stats = TransactionStats(
      paymentCount: 0,
      paymentAmount: 0.0,
      creditCount: 0,
      creditAmount: 0.0,
    );

    // Calculate and set the balance and stats here
    if (transactions.isNotEmpty) {
      netBalance = TransactionService.calculateBalance(transactions);
      stats =
          TransactionService.calculateCustomerTransactionStats(transactions);
    }

    // Always include the AddCreditPaymentButtons
    List<Widget> children = [
      SizedBox(height: 15.0),
      AddCreditPaymentButtons(
        customerName: _customerName,
        customerId: _customerId,
        mobileNumber: _mobileNumber,
      ),
    ];

    // Update the balance summary
    _customerBalanceSummary = BalanceSummary(
      netBalance: netBalance,
      paymentCount: stats.paymentCount,
      paymentAmount: stats.paymentAmount,
      creditCount: stats.creditCount,
      creditAmount: stats.creditAmount,
      children: children,
    );

    // Notify listeners about the change
    notifyListeners();
  }
}
