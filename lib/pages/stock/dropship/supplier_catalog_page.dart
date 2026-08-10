import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasella/models/commerce/cj_supplier_product.dart';
import 'package:pasella/services/commerce_service.dart';
import 'package:pasella/utils/currency_util.dart';

class SupplierCatalogPage extends StatefulWidget {
  const SupplierCatalogPage({
    super.key,
    this.onListingCreated,
    this.searchCatalog,
    this.createListing,
    this.loadSavedProducts,
    this.setSavedProduct,
  });

  final VoidCallback? onListingCreated;
  final CjCatalogSearch? searchCatalog;
  final DropshipListingCreator? createListing;
  final SavedCatalogLoader? loadSavedProducts;
  final SavedCatalogToggle? setSavedProduct;

  @override
  State<SupplierCatalogPage> createState() => _SupplierCatalogPageState();
}

enum _CatalogSort { recommended, lowestCost, fastestDelivery }

class _CatalogCategory {
  const _CatalogCategory(this.label, this.query);

  final String label;
  final String query;
}

const _catalogCategories = <_CatalogCategory>[
  _CatalogCategory('Explore', ''),
  _CatalogCategory('Fashion', 'fashion'),
  _CatalogCategory('Home', 'home'),
  _CatalogCategory('Beauty', 'beauty'),
  _CatalogCategory('Electronics', 'electronics'),
  _CatalogCategory('Baby', 'baby'),
  _CatalogCategory('Accessories', 'accessories'),
];

String _deliveryEstimate(String aging) {
  final value = aging.trim();
  if (value.isEmpty) return 'Delivery time shown when opened';
  return value.toLowerCase().contains('day') ? value : '$value days';
}

int _firstDeliveryDay(String aging) {
  final match = RegExp(r'\d+').firstMatch(aging);
  return int.tryParse(match?.group(0) ?? '') ?? 9999;
}

int dropshipMarkupMinor(String value) =>
    ((double.tryParse(value.replaceAll(',', '.')) ?? 0) * 100).round();

typedef CjCatalogSearch = Future<CjCatalogPage> Function({
  required String query,
  required int page,
  required String cursor,
});

typedef DropshipListingCreator = Future<DropshipListingResult> Function({
  required String supplierProductId,
  required String supplierVariantId,
  required String catalogQuoteVersion,
  required int markupMinor,
});

typedef SavedCatalogLoader = Future<List<CjCatalogProduct>> Function();
typedef SavedCatalogToggle = Future<void> Function(
  CjCatalogProduct product, {
  required bool saved,
});

List<CjCatalogProduct> mergeCjCatalogPages(
  List<CjCatalogProduct> current,
  List<CjCatalogProduct> incoming,
) {
  final byId = <String, CjCatalogProduct>{
    for (final product in current) product.id: product,
  };
  for (final product in incoming) {
    byId[product.id] = product;
  }
  return byId.values.toList(growable: false);
}

class _SupplierCatalogPageState extends State<SupplierCatalogPage> {
  final _search = TextEditingController();
  late final CjCatalogSearch _searchCatalog;
  late final SavedCatalogLoader _loadSavedProducts;
  late final SavedCatalogToggle _setSavedProduct;
  List<CjCatalogProduct> _products = const [];
  List<CjCatalogProduct> _savedProducts = const [];
  final Set<String> _savedIds = {};
  final Set<String> _savingIds = {};
  bool _showSaved = false;
  bool _loadingSaved = false;
  String? _savedError;
  bool _loading = true;
  bool _loadingMore = false;
  int _loadGeneration = 0;
  String? _error;
  String? _loadMoreError;
  int _page = 1;
  int _totalPages = 1;
  int _totalProducts = 0;
  bool _totalProductsExact = true;
  final Map<int, String> _pageCursors = {};
  bool _hasMore = false;
  int _categoryIndex = 0;
  _CatalogSort _sort = _CatalogSort.recommended;
  bool _catalogueRefreshing = false;
  bool _digitalPaymentsEnabled = false;

  String get _query {
    final typed = _search.text.trim();
    return typed.isNotEmpty ? typed : _catalogCategories[_categoryIndex].query;
  }

  List<CjCatalogProduct> get _visibleProducts {
    final products = [...(_showSaved ? _savedProducts : _products)];
    switch (_sort) {
      case _CatalogSort.lowestCost:
        products.sort((a, b) =>
            a.estimatedLandedCostMinor.compareTo(b.estimatedLandedCostMinor));
      case _CatalogSort.fastestDelivery:
        products.sort((a, b) => _firstDeliveryDay(a.logisticAging)
            .compareTo(_firstDeliveryDay(b.logisticAging)));
      case _CatalogSort.recommended:
        break;
    }
    return products;
  }

  @override
  void initState() {
    super.initState();
    _searchCatalog = widget.searchCatalog ?? CommerceService().searchCjCatalog;
    _loadSavedProducts = widget.loadSavedProducts ??
        (widget.searchCatalog == null
            ? CommerceService().listSavedSupplierProducts
            : () async => const []);
    _setSavedProduct = widget.setSavedProduct ??
        (widget.searchCatalog == null
            ? CommerceService().setSupplierProductSaved
            : (CjCatalogProduct _, {required bool saved}) async {});
    _load();
    _refreshSaved();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final loadingMore = page > 1;
    final generation = ++_loadGeneration;
    final query = _query;
    if (!loadingMore) {
      _pageCursors.clear();
      // A fresh query/category always starts a new result set. Resetting the
      // visible page immediately also guarantees that a failed refresh cannot
      // leave its Retry action pointing at stale pagination.
      _page = 1;
    }
    setState(() {
      if (loadingMore) {
        _loadingMore = true;
        _loadMoreError = null;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final result = await _searchCatalog(
        query: query,
        page: page,
        cursor: _pageCursors[page] ?? '',
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _products = loadingMore
            ? mergeCjCatalogPages(_products, result.products)
            : result.products;
        _page = result.page <= 0 ? page : result.page;
        _totalPages = result.totalPages <= 0 ? 1 : result.totalPages;
        _totalProductsExact = result.totalProductsExact;
        _totalProducts = result.totalProductsExact && result.totalProducts > 0
            ? result.totalProducts
            : _products.length;
        _hasMore = result.hasMore;
        if (result.nextCursor.isNotEmpty) {
          _pageCursors[result.page + 1] = result.nextCursor;
        }
        _catalogueRefreshing = result.catalogueRefreshing;
        _digitalPaymentsEnabled = result.digitalPaymentsEnabled;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (loadingMore) {
          _loadMoreError = commerceErrorMessage(error);
          _loadingMore = false;
        } else {
          _error = commerceErrorMessage(error);
          _loading = false;
        }
      });
    }
  }

  void _selectCategory(int index) {
    if (_loading ||
        _loadingMore ||
        index == _categoryIndex && _search.text.isEmpty) {
      return;
    }
    _search.clear();
    setState(() {
      _showSaved = false;
      _categoryIndex = index;
    });
    _load();
  }

  Future<void> _refreshSaved() async {
    setState(() {
      _loadingSaved = true;
      _savedError = null;
    });
    try {
      final products = await _loadSavedProducts();
      if (!mounted) return;
      setState(() {
        _savedProducts = products;
        _savedIds
          ..clear()
          ..addAll(products.map((product) => product.id));
        _loadingSaved = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savedError = commerceErrorMessage(error);
        _loadingSaved = false;
      });
    }
  }

  Future<void> _toggleSaved(CjCatalogProduct product) async {
    if (_savingIds.contains(product.id)) return;
    final wasSaved = _savedIds.contains(product.id);
    setState(() {
      _savingIds.add(product.id);
      if (wasSaved) {
        _savedIds.remove(product.id);
        _savedProducts = _savedProducts
            .where((saved) => saved.id != product.id)
            .toList(growable: false);
      } else {
        _savedIds.add(product.id);
        _savedProducts = [product, ..._savedProducts];
      }
    });
    try {
      await _setSavedProduct(product, saved: !wasSaved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (wasSaved) {
          _savedIds.add(product.id);
          _savedProducts = [product, ..._savedProducts];
        } else {
          _savedIds.remove(product.id);
          _savedProducts = _savedProducts
              .where((saved) => saved.id != product.id)
              .toList(growable: false);
        }
      });
      showCommerceError(context, error);
    } finally {
      if (mounted) setState(() => _savingIds.remove(product.id));
    }
  }

  void _replaceCatalogProduct(CjCatalogProduct product) {
    List<CjCatalogProduct> replace(List<CjCatalogProduct> products) => products
        .map((current) => current.id == product.id ? product : current)
        .toList(growable: false);
    setState(() {
      _products = replace(_products);
      _savedProducts = replace(_savedProducts);
    });
  }

  void _removeUnavailableProduct(String productId) {
    setState(() {
      final removed = _products.any((product) => product.id == productId);
      _products = _products
          .where((product) => product.id != productId)
          .toList(growable: false);
      _savedProducts = _savedProducts
          .map((product) => product.id == productId
              ? product.copyWith(availability: 'unavailable')
              : product)
          .toList(growable: false);
      if (removed && _totalProductsExact && _totalProducts > 0) {
        _totalProducts -= 1;
      }
    });
  }

  void _showSavedProducts() {
    _search.clear();
    setState(() => _showSaved = true);
    _refreshSaved();
  }

  void _searchProducts() {
    if (_loading || _loadingMore) return;
    if (_search.text.trim().isNotEmpty) {
      setState(() {
        _showSaved = false;
        _categoryIndex = 0;
      });
    }
    _load();
  }

  void _onSearchChanged(String _) {
    // A seller can start typing while a page request is still in flight.
    // Invalidate that request immediately so products from the previous query
    // can never be painted under the new search text.
    setState(() {
      if (_loading || _loadingMore) {
        _loadGeneration += 1;
        _loading = false;
        _loadingMore = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 7),
          child: TextField(
            controller: _search,
            enabled: !_loading,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search catalogue',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: _loading || _loadingMore ? null : _searchProducts,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: Color(0xFF258541),
                  width: 1.5,
                ),
              ),
            ),
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _searchProducts(),
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: _catalogCategories.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ChoiceChip(
                  key: const Key('catalog-saved-filter'),
                  selected: _showSaved,
                  avatar: const Icon(Icons.favorite_outline, size: 17),
                  label: Text(
                      'Saved${_savedIds.isEmpty ? '' : ' (${_savedIds.length})'}'),
                  onSelected: (_) => _showSavedProducts(),
                );
              }
              index -= 1;
              final category = _catalogCategories[index];
              return ChoiceChip(
                selected: !_showSaved &&
                    index == _categoryIndex &&
                    _search.text.isEmpty,
                label: Text(category.label),
                visualDensity: VisualDensity.compact,
                labelPadding: const EdgeInsets.symmetric(horizontal: 5),
                onSelected: (_) => _selectCategory(index),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_showSaved && _loadingSaved) {
      return const _CatalogueLoading();
    }
    if (_showSaved && _savedError != null) {
      return _CatalogMessage(
        icon: Icons.refresh_outlined,
        title: 'Could not load saved products',
        message: _savedError!,
        actionLabel: 'Try again',
        action: _refreshSaved,
      );
    }
    if (_loading) {
      return const _CatalogueLoading();
    }
    if (_error != null) {
      return _CatalogMessage(
        icon: Icons.refresh_outlined,
        title: 'Could not refresh products',
        message: _error!,
        actionLabel: 'Try again',
        action: _load,
      );
    }
    if (_showSaved && _savedProducts.isEmpty) {
      return _CatalogMessage(
        icon: Icons.favorite_outline,
        title: 'No saved products yet',
        message: 'Tap the heart on a product to keep it easy to find.',
        actionLabel: 'Explore products',
        action: () {
          setState(() => _showSaved = false);
          if (_products.isEmpty) _load();
        },
      );
    }
    if (!_showSaved && _products.isEmpty) {
      if (_hasMore || _page < _totalPages) {
        return _CatalogMessage(
          icon: Icons.inventory_2_outlined,
          title: 'More products available',
          message: 'Continue to the next delivery-ready results.',
          actionLabel: 'Continue loading products',
          action: () => _load(page: _page + 1),
        );
      }
      if (_catalogueRefreshing) {
        return _CatalogMessage(
          icon: Icons.inventory_2_outlined,
          title: 'Adding matching products',
          message:
              'Spaza One is adding delivery-ready matches in the background. You can keep using the app and try again in a few minutes.',
          actionLabel: 'Refresh results',
          action: () => _load(page: 1),
        );
      }
      return _CatalogMessage(
        icon: Icons.search_off_outlined,
        title: 'No delivery-ready matches',
        message:
            'Try a broader product name or choose another category. Availability changes throughout the day.',
        actionLabel: 'Explore all products',
        action: () {
          _search.clear();
          setState(() => _categoryIndex = 0);
          _load();
        },
      );
    }

    final products = _visibleProducts;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  !_showSaved &&
                          _totalProductsExact &&
                          _totalProducts > products.length
                      ? '${products.length} of $_totalProducts products'
                      : '${products.length} ${products.length == 1 ? 'product' : 'products'}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              PopupMenuButton<_CatalogSort>(
                tooltip: 'Sort products',
                initialValue: _sort,
                icon: const Icon(Icons.sort_rounded),
                onSelected: (value) => setState(() => _sort = value),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _CatalogSort.recommended,
                    child: Text('Recommended'),
                  ),
                  PopupMenuItem(
                    value: _CatalogSort.lowestCost,
                    child: Text('Lowest cost'),
                  ),
                  PopupMenuItem(
                    value: _CatalogSort.fastestDelivery,
                    child: Text('Fastest delivery'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _showSaved ? _refreshSaved : () => _load(page: 1),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: .67,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _SupplierProductCard(
                        key: Key('supplier-product-${products[index].id}'),
                        product: products[index],
                        digitalPaymentsEnabled: _digitalPaymentsEnabled,
                        onListingCreated: widget.onListingCreated,
                        createListing: widget.createListing,
                        onProductChanged: _replaceCatalogProduct,
                        onProductUnavailable: _removeUnavailableProduct,
                        saved: _savedIds.contains(products[index].id),
                        saving: _savingIds.contains(products[index].id),
                        onSavedChanged: () => _toggleSaved(products[index]),
                      ),
                      childCount: products.length,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    child: _LoadMoreProducts(
                      loadedProducts: products.length,
                      totalProducts:
                          _showSaved ? products.length : _totalProducts,
                      loading: _loadingMore,
                      error: _loadMoreError,
                      hasMore: !_showSaved && _hasMore,
                      onPressed:
                          !_showSaved && (_page < _totalPages || _hasMore)
                              ? () => _load(page: _page + 1)
                              : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SupplierProductCard extends StatelessWidget {
  const _SupplierProductCard({
    super.key,
    required this.product,
    required this.digitalPaymentsEnabled,
    required this.onListingCreated,
    required this.createListing,
    required this.onProductChanged,
    required this.onProductUnavailable,
    required this.saved,
    required this.saving,
    required this.onSavedChanged,
  });

  final CjCatalogProduct product;
  final bool digitalPaymentsEnabled;
  final VoidCallback? onListingCreated;
  final DropshipListingCreator? createListing;
  final ValueChanged<CjCatalogProduct> onProductChanged;
  final ValueChanged<String> onProductUnavailable;
  final bool saved;
  final bool saving;
  final VoidCallback onSavedChanged;

  Future<void> _select(BuildContext context) async {
    final result = await showModalBottomSheet<DropshipListingResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CjListingSheet(
        product: product,
        digitalPaymentsEnabled: digitalPaymentsEnabled,
        createListing: createListing,
        onProductChanged: onProductChanged,
        onProductUnavailable: onProductUnavailable,
      ),
    );
    if (result == null || !context.mounted) return;
    final viewProducts = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF258541), size: 56),
            const SizedBox(height: 12),
            const Text(
              'Added to your products',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'It is now available in your Products and WhatsApp catalogue.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  onListingCreated == null ? 'Done' : 'View my products',
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (viewProducts == true && context.mounted) {
      onListingCreated?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: product.isAvailable ? () => _select(context) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.15,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CatalogProductImage(url: product.image),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.white.withValues(alpha: .92),
                      shape: const CircleBorder(),
                      child: IconButton(
                        key: Key('save-supplier-product-${product.id}'),
                        tooltip: saved ? 'Remove from saved' : 'Save product',
                        onPressed: saving ? null : onSavedChanged,
                        icon: saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                saved ? Icons.favorite : Icons.favorite_border,
                                color: saved ? Colors.red.shade600 : null,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const Spacer(),
                    if (!product.isAvailable) ...[
                      Text(
                        product.availability == 'checking'
                            ? 'Checking availability'
                            : 'Currently unavailable',
                        style: TextStyle(
                          color: product.availability == 'checking'
                              ? Colors.orange.shade800
                              : Colors.red.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      '${CurrencyUtil.format(product.estimatedLandedCostMinor / 100)} landed',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(
                          Icons.local_shipping_outlined,
                          size: 15,
                          color: Color(0xFF258541),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            _deliveryEstimate(product.logisticAging),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF258541),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogProductImage extends StatelessWidget {
  const _CatalogProductImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const ColoredBox(
        color: Color(0xFFF0F3F2),
        child: Icon(Icons.inventory_2_outlined),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => const ColoredBox(color: Color(0xFFF0F3F2)),
      errorWidget: (_, __, ___) => const ColoredBox(
        color: Color(0xFFF0F3F2),
        child: Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

class _CjListingSheet extends StatefulWidget {
  const _CjListingSheet({
    required this.product,
    required this.digitalPaymentsEnabled,
    required this.createListing,
    required this.onProductChanged,
    required this.onProductUnavailable,
  });

  final CjCatalogProduct product;
  final bool digitalPaymentsEnabled;
  final DropshipListingCreator? createListing;
  final ValueChanged<CjCatalogProduct> onProductChanged;
  final ValueChanged<String> onProductUnavailable;

  @override
  State<_CjListingSheet> createState() => _CjListingSheetState();
}

class _CjListingSheetState extends State<_CjListingSheet> {
  CommerceService? _commerce;
  final _markup = TextEditingController();
  final _markupFocus = FocusNode();
  final _markupFieldKey = GlobalKey();
  late CjCatalogProduct _product;
  CjVariant? _variant;
  CjLandedQuote? _quote;
  bool _saving = false;
  String? _error;

  int get _markupMinor => dropshipMarkupMinor(_markup.text);
  int get _sellPriceMinor => (_quote?.landedCostMinor ?? 0) + _markupMinor;
  int get _feeMinor => widget.digitalPaymentsEnabled
      ? CommerceService.estimatedFeeMinor(_sellPriceMinor)
      : 0;
  int get _netMarginMinor => _markupMinor - _feeMinor;
  bool get _canCreate =>
      !_saving && _quote != null && _markupMinor > 0 && _netMarginMinor >= 0;
  CommerceService get _commerceService => _commerce ??= CommerceService();

  @override
  void initState() {
    super.initState();
    _applyProduct(widget.product);
  }

  @override
  void dispose() {
    _markupFocus.dispose();
    _markup.dispose();
    super.dispose();
  }

  void _applyProduct(CjCatalogProduct product) {
    final estimate = resolveServerApprovedCatalogEstimate(
      catalogProduct: product,
    );
    _product = product;
    _variant = estimate?.variant;
    _quote = estimate?.quote;
    _error = null;
    if (estimate == null) {
      _error = 'This product is updating. Choose another product for now.';
    }
  }

  Future<void> _create() async {
    final variant = _variant;
    if (variant == null || !_canCreate) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final createListing =
          widget.createListing ?? _commerceService.createListing;
      final result = await createListing(
        supplierProductId: _product.id,
        supplierVariantId: variant.id,
        catalogQuoteVersion: _product.catalogQuoteVersion,
        markupMinor: _markupMinor,
      );
      if (mounted) Navigator.pop(context, result);
    } on DropshipListingQuoteChanged catch (error) {
      if (!mounted) return;
      setState(() {
        _applyProduct(error.product);
        _saving = false;
        _error =
            'Price or delivery changed. Review the updated costs, then tap Add product again.';
      });
      widget.onProductChanged(error.product);
    } on DropshipListingRefreshing catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Updating price and delivery. Try again shortly.';
      });
    } on DropshipListingUnavailable catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _variant = null;
        _quote = null;
        _error = 'This product is no longer available.';
      });
      widget.onProductUnavailable(_product.id);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = commerceErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = keyboard > 0;
    if (keyboardOpen && _markupFocus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final fieldContext = _markupFieldKey.currentContext;
        if (!mounted || fieldContext == null) return;
        Scrollable.ensureVisible(
          fieldContext,
          alignment: .5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }
    return FractionallySizedBox(
      heightFactor: .94,
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: keyboard),
            child: Column(
              children: [
                _sheetHeader(context),
                Expanded(child: _sheetBody(context)),
                if (_quote != null) _bottomAction(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetHeader(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 10, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductImage(url: _product.image, size: 68),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ADD TO MY PRODUCTS',
                      style: TextStyle(
                        color: Color(0xFF258541),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: _saving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _sheetBody(BuildContext context) {
    if (_variant == null || _quote == null) {
      return _CatalogMessage(
        icon: Icons.inventory_2_outlined,
        title: 'Product unavailable right now',
        message:
            _error ?? 'Spaza One could not load a verified product option.',
      );
    }

    final deliveryDetails = _deliveryEstimate(_quote!.logisticAging);

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Option',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                _variant!.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.verified_rounded,
              color: Color(0xFF258541),
              size: 19,
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    color: Color(0xFF9A5A00), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFF7A4800)),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            children: [
              _PriceRow(
                label: 'Estimated product cost',
                value: CurrencyUtil.format(_quote!.productCostMinor / 100),
              ),
              _PriceRow(
                label: 'Estimated delivery',
                value: CurrencyUtil.format(_quote!.shippingCostMinor / 100),
              ),
              const Divider(),
              _PriceRow(
                label: 'Estimated landed cost',
                value: CurrencyUtil.format(_quote!.landedCostMinor / 100),
                emphasized: true,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.local_shipping_outlined,
                      size: 16, color: Color(0xFF258541)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      deliveryDetails,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Set your profit',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Added to the landed cost.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        KeyedSubtree(
          key: _markupFieldKey,
          child: DropshipMarkupField(
            controller: _markup,
            focusNode: _markupFocus,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 14),
        _PriceRow(
          label: 'Customer price',
          value: CurrencyUtil.format(_sellPriceMinor / 100),
          emphasized: true,
        ),
        if (widget.digitalPaymentsEnabled)
          _PriceRow(
            label: 'Estimated payment fee',
            value: '- ${CurrencyUtil.format(_feeMinor / 100)}',
          ),
        _PriceRow(
          label: 'Your estimated margin',
          value: CurrencyUtil.format(_netMarginMinor / 100),
          emphasized: true,
        ),
        if (_markupMinor > 0 && _netMarginMinor < 0)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Increase your markup so it covers the estimated payment fee.',
              style: TextStyle(color: Colors.red),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _bottomAction(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _markupMinor > 0 ? 'Customer price' : 'Set your profit',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  CurrencyUtil.format(_sellPriceMinor / 100),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          ElevatedButton(
            onPressed: _canCreate ? _create : null,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Add product'),
          ),
        ],
      ),
    );
  }
}

class _CatalogueLoading extends StatelessWidget {
  const _CatalogueLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text(
              'Loading products…',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadMoreProducts extends StatelessWidget {
  const _LoadMoreProducts({
    required this.loadedProducts,
    required this.totalProducts,
    required this.loading,
    required this.error,
    required this.hasMore,
    required this.onPressed,
  });

  final int loadedProducts;
  final int totalProducts;
  final bool loading;
  final String? error;
  final bool hasMore;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null && error == null) {
      return Text(
        '$loadedProducts products loaded',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Column(
      children: [
        if (error != null) ...[
          Text(
            'Could not load more products.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('catalog-load-more'),
            onPressed: loading ? null : onPressed,
            icon: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded),
            label: Text(
              loading
                  ? 'Loading products…'
                  : error == null && (hasMore || totalProducts > loadedProducts)
                      ? 'Load more products'
                      : 'Try again',
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? const ColoredBox(
                color: Color(0xFFF0F3F2),
                child: Icon(Icons.inventory_2_outlined),
              )
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => const ColoredBox(
                  color: Color(0xFFF0F3F2),
                ),
                errorWidget: (_, __, ___) => const ColoredBox(
                  color: Color(0xFFF0F3F2),
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
      ),
    );
  }
}

/// Explicitly outlined money input used by the supplier listing sheet.
///
/// Spaza One's global form theme uses underlines. This field deliberately
/// overrides every border state so it continues to read as editable when it
/// is not focused.
class DropshipMarkupField extends StatefulWidget {
  const DropshipMarkupField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.focusNode,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  State<DropshipMarkupField> createState() => _DropshipMarkupFieldState();
}

class _DropshipMarkupFieldState extends State<DropshipMarkupField> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _attachFocusNode(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant DropshipMarkupField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    _detachFocusNode();
    _attachFocusNode(widget.focusNode);
  }

  void _attachFocusNode(FocusNode? externalFocusNode) {
    _ownsFocusNode = externalFocusNode == null;
    _focusNode = externalFocusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  void _detachFocusNode() {
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) _focusNode.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  void _finishEditing() => _focusNode.unfocus();

  @override
  void dispose() {
    _detachFocusNode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('dropship-markup-field'),
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}')),
      ],
      decoration: InputDecoration(
        labelText: 'Profit markup',
        hintText: '0.00',
        prefixText: 'R ',
        suffixIcon: _focusNode.hasFocus
            ? TextButton(
                key: const Key('dropship-markup-done'),
                onPressed: _finishEditing,
                child: const Text('Done'),
              )
            : const Icon(Icons.edit_outlined, size: 20),
        filled: true,
        fillColor: const Color(0xFFF7F9F8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF9AA19C)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF258541),
            width: 2,
          ),
        ),
      ),
      onChanged: widget.onChanged,
      onSubmitted: (_) => _finishEditing(),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogMessage extends StatelessWidget {
  const _CatalogMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: action, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
