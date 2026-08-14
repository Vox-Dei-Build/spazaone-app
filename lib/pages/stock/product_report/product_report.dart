import 'package:flutter/material.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_report/widget/product_section.dart';
import 'package:pasella/pages/stock/product_report/widget/product_summary_card.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/config/size_config.dart';

class ProductReportsTab extends StatelessWidget {
  final StockViewModel viewModel;

  const ProductReportsTab({Key? key, required this.viewModel})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig
    List<Product> allProducts = viewModel.products;
    List<Product> lowStockProducts = viewModel.checkLowStock();
    List<Product> noStockProducts =
        lowStockProducts.where((product) => product.quantity == 0).toList();
    List<Product> lowStockProductsTwo =
        lowStockProducts.where((product) => product.quantity! > 1).toList();

    double totalCost = allProducts.fold(
      0,
      (sum, product) => sum + (product.cost ?? 0) * (product.quantity ?? 0),
    );
    double totalSellingPrice = allProducts.fold(
      0,
      (sum, product) =>
          sum + (product.sellingPrice ?? 0) * (product.quantity ?? 0),
    );
    double potentialProfit = totalSellingPrice - totalCost;

    return ListView(
      padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
      children: [
        SummaryCard(title: 'Product Cost Value', amount: totalCost),
        SummaryCard(title: 'Product Sales Value', amount: totalSellingPrice),
        SummaryCard(title: 'Potential Product Profit', amount: potentialProfit),
        ProductSection(
          title: 'Low-stock Products',
          products: lowStockProductsTwo,
        ),
        ProductSection(
          title: 'Out-of-stock Products',
          products: noStockProducts,
        ),
      ],
    );
  }
}
