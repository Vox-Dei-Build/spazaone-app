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
    final allProducts = viewModel.products
        .where((product) => !product.isDropshipListing)
        .toList(growable: false);
    final lowStockProducts = viewModel
        .checkLowStock()
        .where((product) => !product.isDropshipListing)
        .toList(growable: false);
    List<Product> noStockProducts = lowStockProducts
        .where((product) => (product.quantity ?? 0) <= 0)
        .toList();
    List<Product> lowStockProductsTwo = lowStockProducts
        .where((product) => (product.quantity ?? 0) > 0)
        .toList();

    double totalCost = allProducts.fold(
      0,
      (sum, product) {
        final rawQuantity = product.quantity ?? 0;
        final quantity = rawQuantity < 0 ? 0 : rawQuantity;
        return sum + (product.cost ?? 0) * quantity;
      },
    );
    double totalSellingPrice = allProducts.fold(
      0,
      (sum, product) {
        final rawQuantity = product.quantity ?? 0;
        final quantity = rawQuantity < 0 ? 0 : rawQuantity;
        return sum + (product.sellingPrice ?? 0) * quantity;
      },
    );
    double potentialProfit = totalSellingPrice - totalCost;

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
      children: [
        ProductValueSummary(
          costValue: totalCost,
          salesValue: totalSellingPrice,
          potentialProfit: potentialProfit,
        ),
        const SizedBox(height: 16),
        ProductSection(
          title: 'Needs attention',
          products: [...noStockProducts, ...lowStockProductsTwo],
        ),
      ],
    );
  }
}
