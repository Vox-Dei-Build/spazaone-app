import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasella/models/commerce/cj_supplier_product.dart';
import 'package:pasella/services/commerce_service.dart';
import 'package:pasella/utils/currency_util.dart';

class SupplierCatalogPage extends StatefulWidget {
  const SupplierCatalogPage({super.key});

  @override
  State<SupplierCatalogPage> createState() => _SupplierCatalogPageState();
}

enum _CatalogSort { recommended, lowestCost, fastestDelivery }

class _CatalogCategory {
  const _CatalogCategory(this.label, this.query, this.icon);

  final String label;
  final String query;
  final IconData icon;
}

const _catalogCategories = <_CatalogCategory>[
  _CatalogCategory('Explore', '', Icons.auto_awesome_outlined),
  _CatalogCategory('Fashion', 'fashion', Icons.checkroom_outlined),
  _CatalogCategory('Home', 'home', Icons.home_outlined),
  _CatalogCategory('Beauty', 'beauty', Icons.spa_outlined),
  _CatalogCategory('Electronics', 'electronics', Icons.devices_other_outlined),
  _CatalogCategory('Baby', 'baby', Icons.child_friendly_outlined),
  _CatalogCategory('Accessories', 'accessories', Icons.watch_outlined),
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

class _SupplierCatalogPageState extends State<SupplierCatalogPage> {
  final _search = TextEditingController();
  final _commerce = CommerceService();
  List<CjCatalogProduct> _products = const [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _categoryIndex = 0;
  _CatalogSort _sort = _CatalogSort.recommended;
  bool _digitalPaymentsEnabled = false;

  String get _query {
    final typed = _search.text.trim();
    return typed.isNotEmpty ? typed : _catalogCategories[_categoryIndex].query;
  }

  List<CjCatalogProduct> get _visibleProducts {
    final products = [..._products];
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
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _commerce.searchCjCatalog(
        query: _query,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        _products = result.products;
        _page = result.page <= 0 ? page : result.page;
        _totalPages = result.totalPages <= 0 ? 1 : result.totalPages;
        _digitalPaymentsEnabled = result.digitalPaymentsEnabled;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = commerceErrorMessage(error);
        _loading = false;
      });
    }
  }

  void _selectCategory(int index) {
    if (_loading || index == _categoryIndex && _search.text.isEmpty) return;
    _search.clear();
    setState(() => _categoryIndex = index);
    _load();
  }

  void _searchProducts() {
    if (_loading) return;
    if (_search.text.trim().isNotEmpty) {
      setState(() => _categoryIndex = 0);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'What would you like to sell?',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? IconButton(
                      tooltip: 'Search',
                      onPressed: _loading ? null : _searchProducts,
                      icon: const Icon(Icons.arrow_forward),
                    )
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: _loading
                          ? null
                          : () {
                              _search.clear();
                              setState(() {});
                              _load();
                            },
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _searchProducts(),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: _catalogCategories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = _catalogCategories[index];
              return ChoiceChip(
                selected: index == _categoryIndex && _search.text.isEmpty,
                avatar: Icon(category.icon, size: 17),
                label: Text(category.label),
                onSelected: (_) => _selectCategory(index),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F8F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_outlined,
                    size: 18, color: Color(0xFF258541)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Only products with a recent South Africa delivery option are shown. Price and delivery are checked again before you add one.',
                    style: TextStyle(fontSize: 12, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const _CatalogueLoading();
    }
    if (_error != null) {
      return _CatalogMessage(
        icon: Icons.refresh_outlined,
        title: 'Could not refresh products',
        message: _error!,
        actionLabel: 'Try again',
        action: () => _load(page: _page),
      );
    }
    if (_products.isEmpty) {
      final hasMore = _page < _totalPages;
      return _CatalogMessage(
        icon: Icons.search_off_outlined,
        title: 'No delivery-ready matches',
        message:
            'Try a broader product name or choose another category. Availability changes throughout the day.',
        actionLabel:
            hasMore ? 'Check the next products' : 'Explore all products',
        action: () {
          if (hasMore) {
            _load(page: _page + 1);
            return;
          }
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
                  '${products.length} delivery-ready ${products.length == 1 ? 'product' : 'products'}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<_CatalogSort>(
                  value: _sort,
                  borderRadius: BorderRadius.circular(12),
                  icon: const Icon(Icons.sort, size: 20),
                  items: const [
                    DropdownMenuItem(
                      value: _CatalogSort.recommended,
                      child: Text('Recommended'),
                    ),
                    DropdownMenuItem(
                      value: _CatalogSort.lowestCost,
                      child: Text('Lowest cost'),
                    ),
                    DropdownMenuItem(
                      value: _CatalogSort.fastestDelivery,
                      child: Text('Fastest delivery'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sort = value);
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(page: _page),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
              itemCount: products.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == products.length) {
                  return _Pagination(
                    page: _page,
                    totalPages: _totalPages,
                    previous: _page > 1 ? () => _load(page: _page - 1) : null,
                    next: _page < _totalPages
                        ? () => _load(page: _page + 1)
                        : null,
                  );
                }
                return _SupplierProductCard(
                  product: products[index],
                  digitalPaymentsEnabled: _digitalPaymentsEnabled,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SupplierProductCard extends StatelessWidget {
  const _SupplierProductCard({
    required this.product,
    required this.digitalPaymentsEnabled,
  });

  final CjCatalogProduct product;
  final bool digitalPaymentsEnabled;

  Future<void> _select(BuildContext context) async {
    final result = await showModalBottomSheet<DropshipListingResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CjListingSheet(
        product: product,
        digitalPaymentsEnabled: digitalPaymentsEnabled,
      ),
    );
    if (result == null || !context.mounted) return;
    await showModalBottomSheet<void>(
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
              'Your price is saved and the product is ready to share with customers.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => CommerceService.shareToWhatsApp(
                  title: product.title,
                ),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share on WhatsApp'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPrice = product.estimatedLandedCostMinor > 0;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(90)),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _select(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductImage(url: product.image, size: 96),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F4EA),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'SA DELIVERY OPTION',
                        style: TextStyle(
                          color: Color(0xFF207338),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (product.category.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        product.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      hasPrice
                          ? 'From ${CurrencyUtil.format(product.estimatedLandedCostMinor / 100)} landed'
                          : 'Open to check current price',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
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
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 36),
                child: Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CjListingSheet extends StatefulWidget {
  const _CjListingSheet({
    required this.product,
    required this.digitalPaymentsEnabled,
  });

  final CjCatalogProduct product;
  final bool digitalPaymentsEnabled;

  @override
  State<_CjListingSheet> createState() => _CjListingSheetState();
}

class _CjListingSheetState extends State<_CjListingSheet> {
  final _commerce = CommerceService();
  final _markup = TextEditingController();
  CjProductDetails? _details;
  CjVariant? _variant;
  CjVariant? _checkingVariant;
  CjLandedQuote? _quote;
  bool _loadingDetails = true;
  bool _loadingQuote = false;
  bool _saving = false;
  String? _error;

  int get _markupMinor =>
      ((double.tryParse(_markup.text.replaceAll(',', '.')) ?? 0) * 100).round();
  int get _sellPriceMinor => (_quote?.landedCostMinor ?? 0) + _markupMinor;
  int get _feeMinor => widget.digitalPaymentsEnabled
      ? CommerceService.estimatedFeeMinor(_sellPriceMinor)
      : 0;
  int get _netMarginMinor => _markupMinor - _feeMinor;
  bool get _canCreate =>
      !_saving &&
      !_loadingQuote &&
      _quote != null &&
      _markupMinor > 0 &&
      _netMarginMinor >= 0;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void dispose() {
    _markup.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loadingDetails = true;
      _error = null;
    });
    try {
      final details = await _commerce.getCjProduct(
        widget.product.id,
        preferredVariantId: widget.product.deliverableVariantId,
      );
      final quote = details.recommendedQuote;
      if (!mounted) return;
      if (details.variants.isEmpty || quote == null) {
        setState(() {
          _loadingDetails = false;
          _error =
              'No South Africa delivery option is available right now. Try another product.';
        });
        return;
      }
      final recommendedId = details.recommendedVariantId.isNotEmpty
          ? details.recommendedVariantId
          : quote.variant.id;
      final recommended = details.variants.firstWhere(
        (variant) => variant.id == recommendedId,
        orElse: () => quote.variant,
      );
      setState(() {
        _details = details;
        _variant = recommended;
        _quote = quote;
        _loadingDetails = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingDetails = false;
        _error = commerceErrorMessage(error);
      });
    }
  }

  Future<void> _checkVariant(CjVariant candidate) async {
    final previous = _variant;
    setState(() {
      _checkingVariant = candidate;
      _loadingQuote = true;
      _error = null;
    });
    try {
      final quote = await _commerce.quoteCjVariant(
        productId: widget.product.id,
        variantId: candidate.id,
      );
      if (!mounted || _checkingVariant?.id != candidate.id) return;
      setState(() {
        _variant = candidate;
        _quote = quote;
        _checkingVariant = null;
        _loadingQuote = false;
      });
    } catch (error) {
      if (!mounted || _checkingVariant?.id != candidate.id) return;
      final message = commerceErrorMessage(error);
      final optionUnavailable = message.toLowerCase().contains('variant') ||
          message.toLowerCase().contains('stock') ||
          message.toLowerCase().contains('delivered');
      setState(() {
        _checkingVariant = null;
        _loadingQuote = false;
        _error = optionUnavailable && previous != null
            ? '${candidate.label} is not available for South Africa right now. We kept ${previous.label} selected.'
            : message;
      });
    }
  }

  Future<void> _create() async {
    final variant = _variant;
    if (variant == null || !_canCreate) return;
    setState(() => _saving = true);
    try {
      final result = await _commerce.createListing(
        supplierProductId: widget.product.id,
        supplierVariantId: variant.id,
        markupMinor: _markupMinor,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        showCommerceError(context, error);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
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
              _ProductImage(url: widget.product.image, size: 68),
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
                      widget.product.title,
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
    if (_loadingDetails) {
      return const _QuoteLoading();
    }
    if (_details == null || _quote == null) {
      return _CatalogMessage(
        icon: Icons.inventory_2_outlined,
        title: 'Product needs a fresh check',
        message: _error ??
            'Spaza One could not confirm price and delivery for this product.',
        actionLabel: 'Check again',
        action: _loadDetails,
      );
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        const _VerifiedVariantNotice(),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _variant?.id,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Product option',
            border: OutlineInputBorder(),
          ),
          items: _details!.variants
              .map(
                (variant) => DropdownMenuItem(
                  value: variant.id,
                  child: Text(
                    variant.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: _saving || _loadingQuote
              ? null
              : (id) {
                  final matches =
                      _details!.variants.where((item) => item.id == id);
                  if (matches.isEmpty || matches.first.id == _variant?.id) {
                    return;
                  }
                  _checkVariant(matches.first);
                },
        ),
        if (_loadingQuote) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text(
            'Checking ${_checkingVariant?.label ?? 'this option'} for South Africa…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
                label: 'Product cost',
                value: CurrencyUtil.format(_quote!.productCostMinor / 100),
              ),
              _PriceRow(
                label: 'Estimated delivery',
                value: CurrencyUtil.format(_quote!.shippingCostMinor / 100),
              ),
              const Divider(),
              _PriceRow(
                label: 'Landed cost',
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
                      '${_deliveryEstimate(_quote!.logisticAging)} · ${_quote!.stock} in stock',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _markup,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}')),
          ],
          decoration: const InputDecoration(
            labelText: 'Your profit markup',
            prefixText: 'R ',
            border: OutlineInputBorder(),
            helperText: 'This amount is added to the landed cost.',
          ),
          onChanged: (_) => setState(() {}),
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
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.digitalPaymentsEnabled
                ? 'Customer orders arrive in Spaza One. Confirm the order before placing it with the supplier.'
                : 'Customers order through WhatsApp. Confirm payment in Customer → Orders before placing the supplier order.',
            style: const TextStyle(color: Color(0xFF6F4A00), height: 1.35),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Price and South Africa delivery are checked again when the customer orders. Supplier cost, delivery and your margin are saved with that order.',
          style: TextStyle(fontSize: 12, height: 1.35),
        ),
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
                  _markupMinor > 0 ? 'Customer price' : 'Add your markup',
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

class _VerifiedVariantNotice extends StatelessWidget {
  const _VerifiedVariantNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6ED),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: Color(0xFF258541), size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This option is in stock with delivery to South Africa.',
              style: TextStyle(
                color: Color(0xFF1E6833),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteLoading extends StatelessWidget {
  const _QuoteLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Checking current stock, price and South Africa delivery…',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 6),
            Text(
              'This can take a few seconds.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
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
              'Finding products that deliver to South Africa…',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.totalPages,
    required this.previous,
    required this.next,
  });

  final int page;
  final int totalPages;
  final VoidCallback? previous;
  final VoidCallback? next;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: previous,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Previous'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text('$page / $totalPages'),
          ),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: next,
              icon: const Icon(Icons.chevron_right),
              label: const Text('Next'),
            ),
          ),
        ],
      ),
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
    required this.actionLabel,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback action;

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
            const SizedBox(height: 16),
            OutlinedButton(onPressed: action, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
