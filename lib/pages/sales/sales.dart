import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/sales/widgets/add_sale.dart';
import 'package:pasella/pages/reports/widgets/report_calendar_view.dart';
import 'package:pasella/pages/sales/widgets/sales_list.dart';
import 'package:pasella/pages/sales/widgets/sales_page_header.dart';
import 'package:pasella/pages/sales/widgets/sales_stats_card.dart';
import 'package:provider/provider.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({Key? key}) : super(key: key);

  static const id = '/salesPage';

  @override
  _SalesPageState createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  DateTime? _selectedDay = DateTime.now();
  DateTime? _startDate;
  DateTime? _endDate;

  void _onDateSelected(DateTime selectedDay) {
    setState(() {
      _selectedDay = selectedDay;
      _startDate = null;
      _endDate = null;
    });
  }

  void _onDateRangeSelected(DateTime start, DateTime end) {
    setState(() {
      _startDate = start;
      _endDate = end;
      _selectedDay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return ChangeNotifierProvider(
      create: (_) => SalesViewModel(),
      child: Consumer<SalesViewModel>(
        builder: (context, viewModel, child) {
          return Scaffold(
            floatingActionButton: Padding(
              padding: EdgeInsets.only(
                bottom: SizeConfig.heightMultiplier * 1,
                right: SizeConfig.imageSizeMultiplier * 1,
              ),
              child: SizedBox(
                height:
                    SizeConfig.heightMultiplier * 7, // Adjust height as needed
                child: FloatingActionButton.extended(
                  elevation: 3.0,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AddSale(
                            salesViewModel:
                                viewModel), // Use the same instance of SalesViewModel
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.add_outlined,
                    color: Colors.white,
                    size: SizeConfig.heightMultiplier * 2.5, // Smaller icon
                  ),
                  label: Text(
                    'Add Sale',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize:
                          SizeConfig.textMultiplier * 2, // Adjust font size
                    ),
                  ),
                ),
              ),
            ),
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: SizeConfig.imageSizeMultiplier * 4),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: <Widget>[
                      SizedBox(height: SizeConfig.heightMultiplier * 2),
                      const SalesPageHeader(),
                      SizedBox(height: SizeConfig.heightMultiplier * 2),
                      ReportCalendarView(
                        selectedDay: _selectedDay,
                        startDate: _startDate,
                        endDate: _endDate,
                        onDateSelected: _onDateSelected,
                        onDateRangeSelected: _onDateRangeSelected,
                        onInternalDateSelect: (date) =>
                            viewModel.updateSelectedDate(date),
                        onInternalRangeSelect: (start, end) =>
                            viewModel.updateSelectedDateRange(start, end),
                      ),
                      SizedBox(height: SizeConfig.heightMultiplier * 1.5),
                      SalesStatsCard(
                        viewModel: viewModel,
                        selectedDay: _selectedDay,
                        startDate: _startDate,
                        endDate: _endDate,
                      ),
                      SizedBox(height: SizeConfig.heightMultiplier * 1.5),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height *
                              0.5, // Limit height
                        ),
                        child: SalesList(viewModel: viewModel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
