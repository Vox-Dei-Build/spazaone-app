import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/shared/widgets/balance_summary/balance_summary_card_content.dart';
import 'package:provider/provider.dart';

class BalanceSummaryCard extends StatelessWidget {
  final bool useCustomerProvider;
  final DateTime? startDate;
  final DateTime? endDate;

  const BalanceSummaryCard({
    super.key,
    this.useCustomerProvider = false,
    this.startDate,
    this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    if (useCustomerProvider) {
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
      return Consumer<BalanceSummaryProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              _buildDateRange(),
              BalanceSummaryCardContent(
                balanceSummary: provider.balanceSummary,
              ),
            ],
          );
        },
      );
    }
  }

  Widget _buildDateRange() {
    if (startDate == null || endDate == null) return const SizedBox.shrink();

    String formattedRange = startDate == endDate
        ? _formatDate(startDate!)
        : "${_formatDate(startDate!)} - ${_formatDate(endDate!)}";

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        " $formattedRange",
        style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 1.8,
            fontWeight: FontWeight.w500),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year}";
  }
}
