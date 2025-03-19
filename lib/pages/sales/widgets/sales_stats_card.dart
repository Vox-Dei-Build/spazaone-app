import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/utils/currency_util.dart';

class SalesStatsCard extends StatelessWidget {
  final SalesViewModel viewModel;

  const SalesStatsCard({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 1,
        horizontal: SizeConfig.imageSizeMultiplier * 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SizeConfig.imageSizeMultiplier * 3),
      ),
      elevation: 5.0,
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _buildPeriodText(viewModel.selectedPeriod),
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 2,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatItem(
                  'Total Sales',
                  CurrencyUtil.format(viewModel.totalSales),
                  Colors.blue,
                ),
                _buildStatItem(
                  'Total Cost',
                  CurrencyUtil.format(viewModel.totalCost),
                  Colors.red,
                ),
              ],
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatItem(
                  'Total Profit',
                  CurrencyUtil.format(viewModel.totalProfit),
                  Colors.green,
                ),
                _buildStatItem(
                  'No of Sales',
                  viewModel.totalNumberOfSales.toString(),
                  Colors.purple,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildPeriodText(String selectedPeriod) {
    if (selectedPeriod == "Today") {
      return 'Sales $selectedPeriod';
    } else if (selectedPeriod == "All Time") {
      return '$selectedPeriod Sales';
    } else {
      return 'Sales This $selectedPeriod';
    }
  }

  Widget _buildStatItem(String title, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 1.5,
            color: Colors.grey[600],
          ),
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 0.5),
        Text(
          value,
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 2,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
