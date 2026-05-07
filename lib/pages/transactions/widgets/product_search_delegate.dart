import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/new_product_page/new_product_page.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/utils/string_utils.dart';

class ProductSearchDelegate extends SearchDelegate<Product?> {
  final TransactionViewModel viewModel;

  ProductSearchDelegate({required this.viewModel});

  @override
  void showResults(BuildContext context) {
    viewModel.loadProducts(); // Reload products when showing results
    super.showResults(context);
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    SizeConfig().init(context);

    return [
      IconButton(
        icon: Icon(Icons.clear, size: SizeConfig.imageSizeMultiplier * 6),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    SizeConfig().init(context);

    return IconButton(
      icon: Icon(Icons.arrow_back, size: SizeConfig.imageSizeMultiplier * 6),
      onPressed: () {
        close(context, null);
      },
    );
  }

  // Both the results and suggestions surfaces share the same product
  // list + tap handlers; factor them out so a future refactor can't
  // diverge them silently.
  Widget _buildProductList(BuildContext context) {
    SizeConfig().init(context);

    final List<Product> matchQuery =
        viewModel.filteredProducts.where((product) {
      return product.name!.toLowerCase().contains(query.toLowerCase());
    }).toList();

    if (matchQuery.isEmpty) {
      return ListTile(
        title: Text(
          "No products found. Add a new product.",
          style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
        ),
        leading: Icon(Icons.add, size: SizeConfig.imageSizeMultiplier * 6),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              // Use a distinct name to avoid shadowing the outer
              // `context` we want to pass into `addProduct`.
              builder: (newProductContext) => NewProductPage(
                onProductAdded: (newProduct) async {
                  await viewModel.loadProducts();
                  // Pass the live BuildContext from the delegate, NOT
                  // viewModel.scaffoldKey.currentContext. The shared
                  // ScaffoldKey can be detached during refactors (see
                  // 7cd4126 → 936abcd) and dereffing it with `!`
                  // throws inside an async onTap, which Flutter swallows
                  // on release builds — symptom: tap does nothing.
                  viewModel.addProduct(context, newProduct.id!, 1);
                  close(context, newProduct);
                },
              ),
            ),
          );
        },
      );
    }

    return ListView.builder(
      itemCount: matchQuery.length,
      itemBuilder: (context, index) {
        var result = matchQuery[index];
        return ListTile(
          title: Text(
            formatStringToCamelCase(result.name!),
            style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
          ),
          onTap: () {
            viewModel.addProduct(context, result.id!, 1);
            close(context, result);
          },
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildProductList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildProductList(context);
}
