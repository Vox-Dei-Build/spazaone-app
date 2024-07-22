import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_card/product_card.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';

class ProductList extends StatelessWidget {
  final StockViewModel viewModel;
  final String? groupName;

  const ProductList({Key? key, required this.viewModel, this.groupName})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return StreamBuilder<List<Product>>(
      stream: viewModel.streamProductsByGroup(groupName),
      builder: (BuildContext context, AsyncSnapshot<List<Product>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }
        final products = snapshot.data ?? [];
        if (products.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inbox,
                  size: SizeConfig.imageSizeMultiplier * 20,
                  color: Colors.grey.withOpacity(0.6),
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 2),
                Text(
                  'No products available',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2.5,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 2),
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.7,
              mainAxisSpacing: SizeConfig.heightMultiplier * 1.5,
              crossAxisSpacing: SizeConfig.imageSizeMultiplier * 2,
            ),
            itemCount: products.length,
            itemBuilder: (BuildContext context, int index) {
              return ProductCard(
                product: products[index],
                docID: products[index].id!,
              );
            },
          ),
        );
      },
    );
  }
}
