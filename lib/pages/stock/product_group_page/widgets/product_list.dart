import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_card/product_card.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';

class ProductList extends StatelessWidget {
  final StockViewModel viewModel;
  final String? groupName;

  /// Callback supplied by the parent so the empty state can open the same
  /// product form as the page action. Optional so group drilldowns retain a
  /// simple placeholder.
  final VoidCallback? onAddProduct;

  const ProductList({
    Key? key,
    required this.viewModel,
    this.groupName,
    this.onAddProduct,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return StreamBuilder<List<Product>>(
      stream: viewModel.streamProductsByGroup(groupName),
      builder: (BuildContext context, AsyncSnapshot<List<Product>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text('Could not load products. Please try again.'),
          );
        }
        final products = snapshot.data ?? [];
        if (products.isEmpty) {
          // PAS-UX-04 started by turning the empty catalogue into a
          // recovery surface. Keep Product empty state product-only:
          // merchants opening Products should not be redirected back
          // to Customers, even if this is still their first setup run.
          //
          // The widget is opt-in: nested callers (group drilldown)
          // don't pass handlers and keep the bare placeholder, since
          // an empty group is a different signal than an empty
          // catalogue.
          final showOnboarding = groupName == null && onAddProduct != null;
          return ProductListEmptyState(
            showOnboarding: showOnboarding,
            onAddProduct: onAddProduct,
          );
        }
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 2),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.7,
                  mainAxisSpacing: SizeConfig.heightMultiplier * 1.5,
                  crossAxisSpacing: SizeConfig.imageSizeMultiplier * 2,
                ),
                delegate: SliverChildBuilderDelegate((
                  BuildContext context,
                  int index,
                ) {
                  return ProductCard(
                    key: ValueKey<String>(products[index].id!),
                    product: products[index],
                    docID: products[index].id!,
                  );
                }, childCount: products.length),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Empty-state for the top-level Products catalogue.
///
/// Extracted so widget tests can pump the empty state without a live
/// [StockViewModel] stream or Firestore. Rendered by [ProductList]
/// when the catalogue is empty.
///
/// When [showOnboarding] is true (top-level view + [onAddProduct] supplied),
/// the widget renders a concise action. When false, it falls back to the
/// compact group placeholder.
class ProductListEmptyState extends StatelessWidget {
  const ProductListEmptyState({
    super.key,
    required this.showOnboarding,
    required this.onAddProduct,
  });

  final bool showOnboarding;
  final VoidCallback? onAddProduct;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 6,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 30,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              showOnboarding ? 'No products yet' : 'No products in this group',
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 2.2,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            if (showOnboarding) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onAddProduct,
                icon: const Icon(Icons.add),
                label: const Text('Add product'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: SizeConfig.imageSizeMultiplier * 6,
                    vertical: SizeConfig.heightMultiplier * 1.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
