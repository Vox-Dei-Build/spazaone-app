import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pasella/pages/stock/dropship/dropship_listing_page.dart';
import 'package:pasella/pages/stock/product_details/product_details.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';

class ProductList extends StatelessWidget {
  final StockViewModel viewModel;
  final String? groupName;

  /// Callback supplied by the parent so the empty state can open the same
  /// product form as the page action. Optional so group drilldowns retain a
  /// simple placeholder.
  final VoidCallback? onAddProduct;
  final bool showEmptyAction;

  const ProductList({
    Key? key,
    required this.viewModel,
    this.groupName,
    this.onAddProduct,
    this.showEmptyAction = true,
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
            onAddProduct: showEmptyAction ? onAddProduct : null,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 88),
          itemCount: products.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          itemBuilder: (context, index) => _ProductRow(
            key: ValueKey<String>(products[index].id!),
            product: products[index],
            docID: products[index].id!,
          ),
        );
      },
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    super.key,
    required this.product,
    required this.docID,
  });

  final Product product;
  final String docID;

  @override
  Widget build(BuildContext context) {
    final quantity = product.quantity ?? 0;
    final status = product.isDropshipListing
        ? 'Supplier product'
        : product.whatsappListed
            ? 'Online'
            : quantity <= 5
                ? quantity == 0
                    ? 'Out of stock'
                    : 'Low stock'
                : 'In store';
    return ListTile(
      minVerticalPadding: 12,
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 44,
          height: 44,
          child: product.image?.isNotEmpty == true
              ? CachedNetworkImage(
                  imageUrl: product.image!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const _ProductPlaceholder(),
                )
              : const _ProductPlaceholder(),
        ),
      ),
      title: Text(
        formatStringToCamelCase(product.name ?? 'Product'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        product.isDropshipListing
            ? 'Delivered by supplier'
            : '$quantity in stock',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyUtil.format(product.sellingPrice ?? 0),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                status,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => product.isDropshipListing
              ? DropshipListingPage(product: product, docID: docID)
              : ProductDetailsPage(docID: docID, product: product),
        ),
      ),
    );
  }
}

class _ProductPlaceholder extends StatelessWidget {
  const _ProductPlaceholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: const Icon(Icons.inventory_2_outlined, size: 22),
      );
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
