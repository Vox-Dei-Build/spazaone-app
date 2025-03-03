import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/sales/widgets/add_sale.dart';
import 'package:pasella/pages/sales/widgets/sales_list.dart';
import 'package:pasella/pages/sales/widgets/sales_page_header.dart';
import 'package:pasella/pages/sales/widgets/sales_period_dropdown.dart';
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
                child: Column(
                  children: <Widget>[
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    const SalesPageHeader(),
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    SalesPeriodDropdown(viewModel: viewModel),
                    SizedBox(height: SizeConfig.heightMultiplier * 1.5),
                    SalesStatsCard(viewModel: viewModel),
                    SizedBox(height: SizeConfig.heightMultiplier * 1.5),
                    Expanded(
                      child: SalesList(viewModel: viewModel),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
