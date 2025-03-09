import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/reports/business_report_model.dart';
import 'package:pasella/pages/reports/business_report/view_model/business_report_view_model.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/shared/services/period_filter_services.dart';
import 'package:pasella/pages/reports/widgets/customer_names_display.dart';
import 'package:pasella/pages/reports/widgets/metric_tile.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

class BusinessReportPage extends StatefulWidget {
  const BusinessReportPage({super.key});
  static const id = '/businessReportPage';

  @override
  _BusinessReportPageState createState() => _BusinessReportPageState();
}

class _BusinessReportPageState extends State<BusinessReportPage> {
  late BusinessReportViewModel businessReportViewModel;

  @override
  void initState() {
    super.initState();
    var currentUser = FirebaseAuth.instance.currentUser?.uid ?? '';
    var periodFilterService =
        Provider.of<PeriodFilterService>(context, listen: false);

    businessReportViewModel =
        BusinessReportViewModel(currentUser, periodFilterService);

    businessReportViewModel.reportFutureNotifier.value =
        businessReportViewModel.fetchReport();
  }

  @override
  void dispose() {
    businessReportViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Consumer<BalanceSummaryProvider>(
      builder: (context, balanceSummary, child) {
        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Pay Later Report',
                          style: TextStyle(
                            fontSize: SizeConfig.textMultiplier * 2.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    Card(
                      elevation: 4,
                      child: ValueListenableBuilder<Future<Report>?>(
                        valueListenable:
                            businessReportViewModel.reportFutureNotifier,
                        builder: (context, future, child) {
                          return FutureBuilder<Report>(
                            future: future,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const CircularProgressIndicator();
                              } else if (snapshot.hasError) {
                                print('Error: ${snapshot.error}');
                                return const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Column(children: [
                                      Text(
                                          'Oops something is wrong, please check your network or refresh the page')
                                    ]));
                              } else {
                                Report report = snapshot.data!;
                                return Padding(
                                  padding: EdgeInsets.all(
                                      SizeConfig.imageSizeMultiplier * 4),
                                  child: Column(
                                    children: [
                                      MetricTile(
                                          context,
                                          'Total Owed',
                                          () async => CurrencyUtil.format(
                                              report.cashflowImpact),
                                          false),
                                      MetricTile(context, '% Who Owe You',
                                          () async => report.nplRatio, false),
                                      SizedBox(
                                          height:
                                              SizeConfig.heightMultiplier * 2),
                                      Text(
                                        'Customers (${report.totalNumberofNPAs})',
                                        style: TextStyle(
                                            fontSize:
                                                SizeConfig.textMultiplier * 2.5,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      SizedBox(
                                          height: SizeConfig.heightMultiplier *
                                              1.5),
                                      CustomersWithBadLoansTile(
                                        customersWithBadLoansFuture:
                                            Future.value(
                                                report.customersWithNPAs),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
