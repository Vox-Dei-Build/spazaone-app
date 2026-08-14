import 'package:flutter/material.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_card/product_card.dart';
import 'package:pasella/shared/widgets/responsive_app_layout.dart';

class SearchProductList extends StatelessWidget {
  final List<Product> products;

  const SearchProductList({Key? key, required this.products}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Center(
        child: Text('No products found'),
      );
    }

    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compactResults =
        keyboardVisible || usesCompactLandscapeLayout(context);

    if (compactResults) {
      return ListView.separated(
        key: const Key('compact-product-search-results'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) => SizedBox(
          height: 106,
          child: ProductCard(
            key: ValueKey<String>(products[index].id!),
            product: products[index],
            docID: products[index].id!,
            compactHorizontal: true,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(10),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: constraints.maxWidth >= 620 ? 3 : 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.75,
        ),
        itemCount: products.length,
        itemBuilder: (BuildContext context, int index) {
          return ProductCard(
            key: ValueKey<String>(products[index].id!),
            product: products[index],
            docID: products[index].id!,
          );
        },
      ),
    );
  }
}
