import 'package:flutter/material.dart';
import 'package:pasella/pages/reports/widgets/balance_display.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';

class CustomerReportPage extends StatelessWidget {
  final String customerName;
  final String customerId;

  CustomerReportPage({required this.customerName, required this.customerId});

  @override
  Widget build(BuildContext context) {
    final metrics = {
      'Amount of Loans Captured': '6 (R1500)',
      'Average Repayment Time (Days)': '14 days',
      'Estimated Operating Cashflow Impact (R)': 'R2000',
      'Week with Most Loans Issued': '1st Week of Aug',
      'Number of Reminders Sent': '6 reminders',
    };

    return Scaffold(
        appBar: CustomAppBar(title: 'Report for $customerName'),
        body: SafeArea(
            child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                BalanceDisplay(balance: 'R300'),
                /* MonthlySummaryWidget(), */
                SizedBox(height: 20),
                Text(
                  'Transactions Overview',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),
                /*  TransactionsBarChart(), */
                SizedBox(height: 20),
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: metrics.entries.map((entry) {
                        return ListTile(
                          title: Text(entry.key),
                          trailing: Text(
                            entry.value,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                CustomButton(
                  title: 'Download Report',
                  onTap: () {},
                  color: Colors.green,
                  icon: Icons.download,
                  fontSize: 15.0,
                ),
              ],
            ),
          ),
        )));
  }
}
