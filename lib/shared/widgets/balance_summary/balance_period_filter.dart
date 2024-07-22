import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/period_filter_model.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:provider/provider.dart';

class PeriodFilter extends StatefulWidget {
  final TimePeriod selectedPeriod;
  final Function(TimePeriod) onPeriodChanged;

  const PeriodFilter({
    Key? key,
    required this.selectedPeriod,
    required this.onPeriodChanged,
  }) : super(key: key);

  @override
  _PeriodFilterState createState() => _PeriodFilterState();
}

class _PeriodFilterState extends State<PeriodFilter> {
  late TimePeriod selectedPeriod;

  @override
  void initState() {
    super.initState();
    selectedPeriod = widget.selectedPeriod;
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final balanceSummary =
        Provider.of<BalanceSummaryProvider>(context, listen: false);
    return Opacity(
      opacity: balanceSummary.isLedgerLoading
          ? 0.5
          : 1.0, // Lower opacity when loading
      child: CupertinoSegmentedControl<TimePeriod>(
        children: {
          for (TimePeriod period in TimePeriod.values)
            period: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: SizeConfig.imageSizeMultiplier * 1,
                vertical: SizeConfig.heightMultiplier * 1,
              ),
              child: Text(
                period.name,
                style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.8,
                ),
              ),
            ),
        },
        onValueChanged: !balanceSummary.isLedgerLoading
            ? (TimePeriod newValue) {
                setState(() {
                  selectedPeriod = newValue;
                });
                widget.onPeriodChanged(newValue);
              }
            : (TimePeriod newValue) =>
                null, // You can simply use null here to disable the callback
        groupValue: selectedPeriod,
      ),
    );
  }
}
