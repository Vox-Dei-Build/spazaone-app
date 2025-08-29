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

  @override
  Widget buildResults(BuildContext context) {
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
              builder: (context) => NewProductPage(
                onProductAdded: (newProduct) async {
                  await viewModel.loadProducts(); // Refresh product list
                  viewModel.addProduct(
                      viewModel.scaffoldKey.currentContext!, newProduct.id!, 1);
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
            viewModel.addProduct(
                viewModel.scaffoldKey.currentContext!, result.id!, 1);
            close(context, result);
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
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
              builder: (context) => NewProductPage(
                onProductAdded: (newProduct) async {
                  await viewModel.loadProducts(); // Refresh product list
                  viewModel.addProduct(
                      viewModel.scaffoldKey.currentContext!, newProduct.id!, 1);
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
            viewModel.addProduct(
                viewModel.scaffoldKey.currentContext!, result.id!, 1);
            close(context, result);
          },
        );
      },
    );
  }
}
