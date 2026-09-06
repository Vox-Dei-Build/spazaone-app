import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/spaza_shimmer.dart';
import 'package:pasella/utils/currency_util.dart';

Widget MetricTile(
  BuildContext context,
  String title,
  Future<dynamic> Function() fetchMetric,
  bool isCurrency,
) {
  SizeConfig().init(context);

  return FutureBuilder<dynamic>(
    future: fetchMetric(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SpazaShimmer(
          semanticsLabel: 'Loading report metric',
          child: ListTile(
            title: SpazaSkeletonLine(widthFactor: .45, height: 12),
            trailing: SpazaSkeletonBox(height: 16, width: 72),
          ),
        );
      } else if (snapshot.hasError) {
        return const Text('Unavailable');
      } else {
        String displayValue;
        if (snapshot.data is num && isCurrency) {
          displayValue = CurrencyUtil.format(snapshot.data as double);
        } else {
          displayValue = snapshot.data.toString();
        }
        return ListTile(
          title: Text(
            title,
            style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
          ),
          trailing: Text(
            displayValue,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: SizeConfig.textMultiplier * 2,
            ),
          ),
        );
      }
    },
  );
}
