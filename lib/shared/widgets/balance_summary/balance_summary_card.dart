import 'package:flutter/material.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/shared/widgets/balance_summary/balance_summary_card_content.dart';
import 'package:provider/provider.dart';

class BalanceSummaryCard extends StatelessWidget {
  final bool useCustomerProvider;

  BalanceSummaryCard({this.useCustomerProvider = false});

  @override
  Widget build(BuildContext context) {
    if (useCustomerProvider) {
      // Use CustomerBalanceSummaryProvider
      return Consumer<CustomerBalanceSummaryProvider>(
        builder: (context, customerProvider, child) {
          return Column(
            children: [
              BalanceSummaryCardContent(
                balanceSummary: customerProvider.customerBalanceSummary,
              ),
            ],
          );
        },
      );
    } else {
      // Use BalanceSummaryProvider
      return Consumer<BalanceSummaryProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              BalanceSummaryCardContent(
                balanceSummary: provider.balanceSummary,
              ),
            ],
          );
        },
      );
    }
  }
}
