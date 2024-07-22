import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/pages/sales/widgets/sale_detail_page.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:shimmer/shimmer.dart';

class SalesList extends StatelessWidget {
  final SalesViewModel viewModel;

  SalesList({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return StreamBuilder<List<Sale>>(
      stream: viewModel.sales,
      builder: (BuildContext context, AsyncSnapshot<List<Sale>> snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        switch (snapshot.connectionState) {
          case ConnectionState.waiting:
            return _buildShimmerPlaceholder(context);
          default:
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                  child: Text("No sales data available",
                      style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 2.5)));
            }
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final sale = snapshot.data![index];

                return Card(
                  margin: EdgeInsets.symmetric(
                      vertical: SizeConfig.heightMultiplier * 0.5,
                      horizontal: SizeConfig.imageSizeMultiplier * 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                        SizeConfig.imageSizeMultiplier * 2),
                  ),
                  elevation: 3.0,
                  child: ListTile(
                    contentPadding: EdgeInsets.symmetric(
                        vertical: SizeConfig.heightMultiplier * 0.5,
                        horizontal: SizeConfig.imageSizeMultiplier * 2),
                    title: Text(
                      "Date: ${DateFormat("dd-MM-yyyy HH:mm").format(sale.dateAdded)}",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: SizeConfig.textMultiplier * 2.1),
                    ),
                    subtitle: Text(
                      "Amount: ${CurrencyUtil.format(sale.amount)}",
                      style: TextStyle(
                          color: Colors.green,
                          fontSize: SizeConfig.textMultiplier * 1.9),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios,
                        size: SizeConfig.imageSizeMultiplier * 4,
                        color: Colors.grey),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => SaleDetailPage(sale: sale),
                        ),
                      );
                    },
                  ),
                );
              },
            );
        }
      },
    );
  }

  Widget _buildShimmerPlaceholder(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List<Widget>.filled(
          5,
          Padding(
            padding: EdgeInsets.symmetric(
                vertical: SizeConfig.heightMultiplier * 0.5,
                horizontal: SizeConfig.imageSizeMultiplier * 2),
            child: Shimmer.fromColors(
              baseColor: Colors.black12,
              highlightColor: Colors.black26,
              child: Container(
                width: SizeConfig.screenWidth,
                height: SizeConfig.heightMultiplier * 2,
                decoration: BoxDecoration(
                  color: Colors.grey,
                  borderRadius: BorderRadius.all(
                      Radius.circular(SizeConfig.imageSizeMultiplier * 2)),
                ),
              ),
            ),
          ),
          growable: false,
        ),
      ),
    );
  }
}
