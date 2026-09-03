import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/models/stock/whatsapp_catalog_status.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pasella/pages/stock/dropship/dropship_listing_page.dart';
import 'package:pasella/pages/stock/product_details/product_details.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/pages/settings/share/share.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/shared/widgets/responsive_app_layout.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';
import 'package:pasella/utils/support_util.dart';

class ProductList extends StatelessWidget {
  final StockViewModel viewModel;
  final String? groupName;

  /// Callback supplied by the parent so the empty state can open the same
  /// product form as the page action. Optional so group drilldowns retain a
  /// simple placeholder.
  final VoidCallback? onAddProduct;
  final bool showEmptyAction;
  final WhatsAppCatalogSnapshot? catalogSnapshot;
  final Future<void> Function()? onCatalogRefresh;
  final Future<void> Function()? onProductChanged;

  const ProductList({
    Key? key,
    required this.viewModel,
    this.groupName,
    this.onAddProduct,
    this.showEmptyAction = true,
    this.catalogSnapshot,
    this.onCatalogRefresh,
    this.onProductChanged,
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
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _ProductRow(
            key: ValueKey<String>(products[index].id!),
            product: products[index],
            docID: products[index].id!,
            catalogState: catalogSnapshot?.productsById[products[index].id],
            rollout: catalogSnapshot?.rollout,
            onCatalogRefresh: onCatalogRefresh,
            onProductChanged: onProductChanged,
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
    this.catalogState,
    this.rollout,
    this.onCatalogRefresh,
    this.onProductChanged,
  });

  final Product product;
  final String docID;
  final WhatsAppCatalogProductState? catalogState;
  final WhatsAppCatalogRollout? rollout;
  final Future<void> Function()? onCatalogRefresh;
  final Future<void> Function()? onProductChanged;

  @override
  Widget build(BuildContext context) {
    final quantity = product.quantity ?? 0;
    final status = _statusLabel(quantity);
    return Material(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: .42),
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        minVerticalPadding: 10,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.isDropshipListing
                  ? 'Delivered by supplier'
                  : '$quantity in stock',
            ),
            Semantics(
              button: catalogState?.action != null &&
                  catalogState?.action != WhatsAppCatalogProductAction.none,
              label: 'WhatsApp catalogue status: $status',
              child: InkWell(
                onTap: catalogState?.action == WhatsAppCatalogProductAction.none
                    ? null
                    : () => _openStatusAction(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _statusColor(context),
                            ),
                      ),
                    ),
                    if (catalogState?.action != null &&
                        catalogState?.action !=
                            WhatsAppCatalogProductAction.none)
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: _statusColor(context),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              CurrencyUtil.format(product.sellingPrice ?? 0),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        onTap: () => _openProduct(context),
      ),
    );
  }

  String _statusLabel(int quantity) {
    final state = catalogState;
    if (state != null) {
      if (rollout == WhatsAppCatalogRollout.notEnabled &&
          state.reasonCodes.contains('catalogue_not_enabled')) {
        return 'Waiting for rollout';
      }
      return state.status.label;
    }
    if (product.isDropshipListing) return 'Supplier product';
    if (product.whatsappListed) return 'WhatsApp listing requested';
    if (quantity <= 5) return quantity == 0 ? 'Out of stock' : 'Low stock';
    return 'In store';
  }

  Color _statusColor(BuildContext context) {
    return switch (catalogState?.status) {
      WhatsAppCatalogProductStatus.live => Colors.green.shade700,
      WhatsAppCatalogProductStatus.needsAttention ||
      WhatsAppCatalogProductStatus.reviewRequired ||
      WhatsAppCatalogProductStatus.supportReview =>
        Theme.of(context).colorScheme.error,
      WhatsAppCatalogProductStatus.syncing ||
      WhatsAppCatalogProductStatus.stale ||
      WhatsAppCatalogProductStatus.removalSyncing =>
        Colors.orange.shade800,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  Future<void> _openProduct(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => product.isDropshipListing
            ? DropshipListingPage(product: product, docID: docID)
            : ProductDetailsPage(docID: docID, product: product),
      ),
    );
    await onProductChanged?.call();
  }

  Future<void> _openStatusAction(BuildContext context) async {
    final state = catalogState;
    if (state == null) return;
    await TelemetryService.instance.capture(
      WhatsAppCatalogStatusActionOpened(
        status: state.status.wireValue,
        action: state.action.wireValue,
      ),
    );
    if (!context.mounted) return;
    switch (state.action) {
      case WhatsAppCatalogProductAction.none:
        return;
      case WhatsAppCatalogProductAction.editProduct:
        await _openProduct(context);
      case WhatsAppCatalogProductAction.completeShopLink:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SharePage(source: 'catalog_status'),
          ),
        );
        await onProductChanged?.call();
      case WhatsAppCatalogProductAction.refresh:
        await onCatalogRefresh?.call();
      case WhatsAppCatalogProductAction.contactSupport:
        final reference = state.supportReference;
        await SupportUtil.sendWhatsAppMessage(
          context,
          WhatsAppMessageType.support,
          messageOverride:
              'Hi Spaza One Support, I need help with my WhatsApp catalogue. '
              '${reference == null ? '' : 'Reference: $reference'}',
        );
    }
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
    return ScrollableCenteredContent(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 6,
        vertical: 12,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
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
    );
  }
}
