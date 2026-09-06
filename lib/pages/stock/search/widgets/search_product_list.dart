import 'package:flutter/material.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_card/product_card.dart';
import 'package:pasella/shared/widgets/responsive_app_layout.dart';

class SearchProductList extends StatelessWidget {
  final List<Product> products;
  final ValueChanged<Product>? onOpenProduct;

  const SearchProductList(
      {Key? key, required this.products, this.onOpenProduct})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Center(
        child: Text('No products found'),
      );
    }

    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compactResults = keyboardVisible ||
        usesCompactLandscapeLayout(context) ||
        MediaQuery.textScalerOf(context).scale(14) >= 20;

    if (compactResults) {
      return ListView.separated(
        key: const Key('compact-product-search-results'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 106),
          child: ProductCard(
            key: ValueKey<String>(products[index].id!),
            product: products[index],
            docID: products[index].id!,
            onOpen: onOpenProduct == null
                ? null
                : () => onOpenProduct!(products[index]),
            compactHorizontal: true,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
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
            onOpen: onOpenProduct == null
                ? null
                : () => onOpenProduct!(products[index]),
          );
        },
      ),
    );
  }
}
