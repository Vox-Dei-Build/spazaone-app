import 'package:flutter/material.dart';
import 'package:pasella/models/stock/product_group_model.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'product_group_card.dart';

class ProductGroupList extends StatelessWidget {
  final StockViewModel viewModel;

  const ProductGroupList({Key? key, required this.viewModel}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProductGroup>>(
      stream: viewModel.streamProductGroups(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final productGroups = snapshot.data ?? [];

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                ),
                itemCount: productGroups.length,
                itemBuilder: (context, index) {
                  final groupName = productGroups[index].name;
                  if (groupName != null) {
                    return StreamBuilder<int>(
                      stream: viewModel.getProductCount(groupName),
                      builder: (context, countSnapshot) {
                        if (countSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return ProductGroupCard(
                              viewModel: viewModel, name: groupName);
                        }
                        if (countSnapshot.hasError) {
                          return ProductGroupCard(
                              viewModel: viewModel, name: groupName);
                        }
                        final productCount = countSnapshot.data ?? 0;
                        return ProductGroupCard(
                          viewModel: viewModel,
                          name: groupName,
                          productCount: productCount,
                        );
                      },
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
