import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/utils/currency_util.dart';

class MonthlySummaryWidget extends StatelessWidget {
  final double totalCredit;

  MonthlySummaryWidget({required this.totalCredit});

  Future<Map<String, double>> _fetchMonthlySummaries() async {
    Map<String, double> monthlySummaries = {};

    DateTime now = DateTime.now();
    for (int i = 0; i < 3; i++) {
      int monthIndex = now.month - i.toInt() - 1;
      monthlySummaries[DateFormat('MMMM')
          .format(DateTime(now.year, monthIndex))] = totalCredit;
    }

    return monthlySummaries;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, double>>(
      future: _fetchMonthlySummaries(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          Map<String, double> monthlySummaries = snapshot.data ?? {};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Monthly Summary',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              ...monthlySummaries.entries.map((entry) {
                return ListTile(
                  title: Text(entry.key),
                  trailing: Text(CurrencyUtil.format(entry.value)),
                );
              }).toList(),
            ],
          );
        }
      },
    );
  }
}
