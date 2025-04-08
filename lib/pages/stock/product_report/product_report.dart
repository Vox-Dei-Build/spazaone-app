import 'package:flutter/material.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_report/widget/product_section.dart';
import 'package:pasella/pages/stock/product_report/widget/product_summary_card.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/config/size_config.dart';

class ProductReportsTab extends StatefulWidget {
  final StockViewModel viewModel;

  const ProductReportsTab({Key? key, required this.viewModel})
      : super(key: key);

  @override
  _ProductReportsTabState createState() => _ProductReportsTabState();
}

class _ProductReportsTabState extends State<ProductReportsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lowStockProducts = widget.viewModel.checkLowStock();
      for (var product in lowStockProducts) {
        if (product.quantity! < 1) {
          showSnackbar(context,
              '${product.name} is finished, please restock :(', Colors.red);
        } else {
          showSnackbar(
              context,
              '${product.name} only has ${product.quantity} item(s) left. Stock soon ;)',
              Colors.orange);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig
    List<Product> allProducts = widget.viewModel.products;
    List<Product> lowStockProducts = widget.viewModel.checkLowStock();
    List<Product> noStockProducts =
        lowStockProducts.where((product) => product.quantity == 0).toList();
    List<Product> lowStockProductsTwo =
        lowStockProducts.where((product) => product.quantity! > 1).toList();

    double totalCost = allProducts.fold(0,
        (sum, product) => sum + (product.cost ?? 0) * (product.quantity ?? 0));
    double totalSellingPrice = allProducts.fold(
        0,
        (sum, product) =>
            sum + (product.sellingPrice ?? 0) * (product.quantity ?? 0));
    double potentialProfit = totalSellingPrice - totalCost;

    return ListView(
      padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
      children: [
        SummaryCard(title: 'Product(s) Cost Value', amount: totalCost),
        SummaryCard(title: 'Product(s) Sales Value', amount: totalSellingPrice),
        SummaryCard(
            title: 'Potential Profit from Product(s)', amount: potentialProfit),
        ProductSection(
            title: 'Almost Finished Product(s)', products: lowStockProductsTwo),
        ProductSection(title: 'Finished Product(s)', products: noStockProducts),
      ],
    );
  }
}
