import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:pasella/utils/currency_util.dart';

class TransactionsBarChart extends StatelessWidget {
  final double totalCredit;

  TransactionsBarChart({required this.totalCredit});

  Future<List<BarChartGroupData>> _fetchBarChartData() async {
    List<BarChartGroupData> barGroups = [];
    for (int i = 0; i < 3; i++) {
      barGroups.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: totalCredit, color: Colors.blue),
      ]));
    }

    return barGroups;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BarChartGroupData>>(
      future: _fetchBarChartData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          List<BarChartGroupData> barGroups = snapshot.data ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: 220,
                child: BarChart(
                  BarChartData(
                    barGroups: barGroups,
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, _) {
                            DateTime now = DateTime.now();
                            int monthIndex = now.month - value.toInt() - 1;
                            return Text(
                              DateFormat('MMMM')
                                  .format(DateTime(now.year, monthIndex)),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 55,
                          getTitlesWidget: (value, _) {
                            return Text(CurrencyUtil.format(value));
                          },
                        ),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: false,
                        ),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      },
    );
  }
}
