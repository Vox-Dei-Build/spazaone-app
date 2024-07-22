import 'package:flutter/material.dart';
import 'package:pasella/models/common/balance_summary_model.dart';
import 'package:pasella/shared/widgets/balance_summary/info_row.dart';

class CustomerStats extends StatelessWidget {
  final BalanceSummary balanceSummary;
  final Color balanceColor;

  const CustomerStats(
      {Key? key, required this.balanceSummary, required this.balanceColor})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    var totalCustomers = balanceSummary.totalCustomers;
    var owingNumberOfCustomers = balanceSummary.owingNumberOfCustomers;
    return totalCustomers != null && owingNumberOfCustomers != null
        ? Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InfoRow(label: "Total Customers", value: "$totalCustomers"),
              InfoRow(
                  label: "Owing Customers", value: "$owingNumberOfCustomers"),
            ],
          )
        : SizedBox.shrink();
  }
}
