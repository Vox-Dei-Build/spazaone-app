import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/models/stock/whatsapp_catalog_status.dart';
import 'package:pasella/pages/settings/share/share.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/utils/support_util.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pasella/pages/stock/dropship/dropship_listing_page.dart';
import 'package:pasella/pages/stock/product_details/product_details.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/shared/widgets/responsive_app_layout.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';

class ProductList extends StatefulWidget {
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
  final Widget? header;

  const ProductList({
    Key? key,
    required this.viewModel,
    this.groupName,
    this.onAddProduct,
    this.showEmptyAction = true,
    this.catalogSnapshot,
    this.onCatalogRefresh,
    this.onProductChanged,
    this.header,
  }) : super(key: key);

  @override
  State<ProductList> createState() => _ProductListState();
}

class _ProductListState extends State<ProductList> {
  late Stream<List<Product>> _productsStream;

  @override
  void initState() {
    super.initState();
    _productsStream = widget.viewModel.streamProductsByGroup(widget.groupName);
  }

  @override
  void didUpdateWidget(covariant ProductList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel ||
        oldWidget.groupName != widget.groupName) {
      _productsStream =
          widget.viewModel.streamProductsByGroup(widget.groupName);
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return StreamBuilder<List<Product>>(
      stream: _productsStream,
      builder: (BuildContext context, AsyncSnapshot<List<Product>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _withHeader(const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ));
        }
        if (snapshot.hasError) {
          return _withHeader(const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text('Could not load products. Please try again.'),
            ),
          ));
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
          final showOnboarding =
              widget.groupName == null && widget.onAddProduct != null;
          final emptyState = ProductListEmptyState(
            showOnboarding: showOnboarding,
            onAddProduct: widget.showEmptyAction ? widget.onAddProduct : null,
          );
          return _withHeader(emptyState);
        }
        return ProductCatalogueView(
          products: products,
          showFilters: widget.groupName == null,
          header: widget.header,
          catalogSnapshot: widget.catalogSnapshot,
          onOpenProduct: _openProduct,
          onCatalogAction: _openStatusAction,
        );
      },
    );
  }

  Widget _withHeader(Widget content) => widget.header == null
      ? content
      : ListView(children: [widget.header!, content]);

  Future<void> _openProduct(Product product) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => product.isDropshipListing
            ? DropshipListingPage(product: product, docID: product.id!)
            : ProductDetailsPage(docID: product.id!, product: product),
      ),
    );
    if (!mounted) return;
    await widget.onProductChanged?.call();
  }

  Future<void> _openStatusAction(Product product) async {
    final state = widget.catalogSnapshot?.productsById[product.id];
    if (state == null || state.action == WhatsAppCatalogProductAction.none) {
      return;
    }
    await TelemetryService.instance.capture(
      WhatsAppCatalogStatusActionOpened(
        status: state.status.wireValue,
        action: state.action.wireValue,
      ),
    );
    if (!mounted) return;
    switch (state.action) {
      case WhatsAppCatalogProductAction.none:
        return;
      case WhatsAppCatalogProductAction.editProduct:
        await _openProduct(product);
      case WhatsAppCatalogProductAction.completeShopLink:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SharePage(source: 'catalog_status'),
          ),
        );
        if (!mounted) return;
        await widget.onProductChanged?.call();
      case WhatsAppCatalogProductAction.refresh:
        await widget.onCatalogRefresh?.call();
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

enum _StockFilter { all, low, out }

/// Presentational catalogue shared by the live page and local previews.
/// Stock filters use the same five-unit threshold as the stock report, while
/// supplier-fulfilled products and unset quantities do not imply local stock.
class ProductCatalogueView extends StatefulWidget {
  const ProductCatalogueView({
    super.key,
    required this.products,
    required this.onOpenProduct,
    this.showFilters = true,
    this.catalogSnapshot,
    this.onCatalogAction,
    this.header,
  });

  final List<Product> products;
  final ValueChanged<Product> onOpenProduct;
  final bool showFilters;
  final WhatsAppCatalogSnapshot? catalogSnapshot;
  final ValueChanged<Product>? onCatalogAction;
  final Widget? header;

  @override
  State<ProductCatalogueView> createState() => _ProductCatalogueViewState();
}

class _ProductCatalogueViewState extends State<ProductCatalogueView> {
  _StockFilter _filter = _StockFilter.all;

  bool _matches(Product product, _StockFilter filter) {
    if (filter == _StockFilter.all) return true;
    if (product.isDropshipListing || product.quantity == null) return false;
    final quantity = product.quantity!;
    return filter == _StockFilter.low
        ? quantity > 0 && quantity <= 5
        : quantity <= 0;
  }

  @override
  Widget build(BuildContext context) {
    final activeFilter = widget.showFilters ? _filter : _StockFilter.all;
    final visible = widget.products
        .where((product) => _matches(product, activeFilter))
        .toList();
    final lowCount = widget.products
        .where((product) => _matches(product, _StockFilter.low))
        .length;
    final outCount = widget.products
        .where((product) => _matches(product, _StockFilter.out))
        .length;
    return CustomScrollView(
      key: const ValueKey('product-catalogue-scroll'),
      slivers: [
        if (widget.header != null) SliverToBoxAdapter(child: widget.header),
        if (widget.showFilters)
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
              child: Row(
                children: [
                  _filterChip(_StockFilter.all, 'All', widget.products.length),
                  const SizedBox(width: 8),
                  _filterChip(_StockFilter.low, 'Low stock', lowCount),
                  const SizedBox(width: 8),
                  _filterChip(_StockFilter.out, 'Out of stock', outCount),
                ],
              ),
            ),
          ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      size: 32, color: kSecondaryAccent),
                  const SizedBox(height: 12),
                  Text(
                    activeFilter == _StockFilter.low
                        ? 'No products running low'
                        : activeFilter == _StockFilter.out
                            ? 'No products out of stock'
                            : 'No products yet',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: kTertiaryColor,
                        ),
                  ),
                  if (activeFilter != _StockFilter.all) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          setState(() => _filter = _StockFilter.all),
                      child: const Text('Show all products'),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 24),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (context, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => ProductCatalogueRow(
                key: ValueKey(visible[index].id ?? visible[index]),
                product: visible[index],
                catalogState:
                    widget.catalogSnapshot?.productsById[visible[index].id],
                rollout: widget.catalogSnapshot?.rollout,
                onCatalogAction: widget.onCatalogAction == null
                    ? null
                    : () => widget.onCatalogAction!(visible[index]),
                onTap: () => widget.onOpenProduct(visible[index]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _filterChip(_StockFilter filter, String label, int count) {
    final colors = Theme.of(context).colorScheme;
    final selected = _filter == filter;
    return ChoiceChip(
      key: ValueKey('product-filter-${filter.name}'),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _filter = filter),
      label: Text('$label  $count'),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: selected ? colors.primary : SpazaColors.muted,
      ),
      selectedColor: SpazaColors.selected,
      backgroundColor: colors.surface.withValues(alpha: 0),
      side: BorderSide(
        color: selected
            ? colors.primary.withValues(alpha: .25)
            : SpazaColors.border,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
    );
  }
}

/// Product identity, selling price and stock status remain independent so an
/// online listing never hides an out-of-stock warning.
class ProductCatalogueRow extends StatelessWidget {
  const ProductCatalogueRow({
    super.key,
    required this.product,
    required this.onTap,
    this.catalogState,
    this.rollout,
    this.onCatalogAction,
  });

  final Product product;
  final VoidCallback onTap;
  final WhatsAppCatalogProductState? catalogState;
  final WhatsAppCatalogRollout? rollout;
  final VoidCallback? onCatalogAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final quantity = product.quantity;
    final isOut =
        !product.isDropshipListing && quantity != null && quantity <= 0;
    final isLow = !product.isDropshipListing &&
        quantity != null &&
        quantity > 0 &&
        quantity <= 5;
    final stockLabel = product.isDropshipListing
        ? 'Supplier fulfilled'
        : quantity == null
            ? 'Stock not set'
            : isOut
                ? 'Out of stock'
                : isLow
                    ? 'Low stock · $quantity left'
                    : '$quantity in stock';
    final statusColor = isOut
        ? colors.error
        : isLow
            ? const Color(0xFF906000)
            : kSecondaryAccent;
    final name = formatStringToCamelCase(
      product.name?.trim().isNotEmpty == true ? product.name! : 'Product',
    );
    final price = CurrencyUtil.format(product.sellingPrice ?? 0);

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
        side: const BorderSide(color: SpazaColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 80),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final priceStyle = theme.textTheme.titleSmall?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: kTertiaryColor,
                );
                final pricePainter = TextPainter(
                  text: TextSpan(text: price, style: priceStyle),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                // Keep room for the name after the image, price and arrow.
                final nameSpace =
                    constraints.maxWidth - 60 - 12 - 26 - pricePainter.width;
                pricePainter.dispose();
                final stacked = constraints.maxWidth < 260 ||
                    MediaQuery.textScalerOf(context).scale(14) > 19 ||
                    nameSpace < 120;
                final priceText = Text(
                  price,
                  style: priceStyle,
                );
                final priceAndArrow = Row(
                  key: const ValueKey('product-price-and-arrow'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (stacked) Expanded(child: priceText) else priceText,
                    const SizedBox(width: 8),
                    const Icon(SpazaIcons.next,
                        size: 18, color: kSecondaryAccent),
                  ],
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: product.image?.isNotEmpty == true
                            ? CachedNetworkImage(
                                imageUrl: product.image!,
                                fit: BoxFit.cover,
                                placeholder: (_, __) =>
                                    const _ProductPlaceholder(),
                                errorWidget: (_, __, ___) =>
                                    const _ProductPlaceholder(),
                              )
                            : const _ProductPlaceholder(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: kTertiaryColor,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              if (!stacked) ...[
                                const SizedBox(width: 12),
                                priceAndArrow,
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                stockLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: statusColor,
                                  fontWeight: isOut || isLow
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                          if (catalogState != null || product.whatsappListed)
                            _catalogStatus(context),
                          if (stacked) ...[
                            const SizedBox(height: 6),
                            priceAndArrow,
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _catalogStatus(BuildContext context) {
    final state = catalogState;
    final label = state == null
        ? 'WhatsApp listing requested'
        : rollout == WhatsAppCatalogRollout.notEnabled &&
                state.reasonCodes.contains('catalogue_not_enabled')
            ? 'Waiting for rollout'
            : state.status.label;
    final color = switch (state?.status) {
      WhatsAppCatalogProductStatus.live => SpazaColors.action,
      WhatsAppCatalogProductStatus.needsAttention ||
      WhatsAppCatalogProductStatus.reviewRequired ||
      WhatsAppCatalogProductStatus.supportReview =>
        Theme.of(context).colorScheme.error,
      WhatsAppCatalogProductStatus.syncing ||
      WhatsAppCatalogProductStatus.stale ||
      WhatsAppCatalogProductStatus.removalSyncing =>
        const Color(0xFF906000),
      _ => SpazaColors.muted,
    };
    final canAct = state != null &&
        state.action != WhatsAppCatalogProductAction.none &&
        onCatalogAction != null;
    final labelWidget = Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
    );
    return Semantics(
      button: canAct,
      label: 'WhatsApp catalogue status: $label',
      excludeSemantics: true,
      child: canAct
          ? InkWell(
              onTap: onCatalogAction,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: labelWidget),
                    const SizedBox(width: 4),
                    Icon(Icons.info_outline, size: 16, color: color),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: labelWidget,
            ),
    );
  }
}

class _ProductPlaceholder extends StatelessWidget {
  const _ProductPlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: SpazaColors.subtle,
        child: Icon(
          SpazaIcons.products,
          size: 23,
          color: SpazaColors.muted,
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: SpazaColors.subtle,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 30,
              color: SpazaColors.muted,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            showOnboarding ? 'No products yet' : 'No products in this group',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: kTertiaryColor,
                ),
            textAlign: TextAlign.center,
          ),
          if (showOnboarding && onAddProduct != null) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onAddProduct,
              icon: const Icon(Icons.add),
              label: const Text('Add product'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
