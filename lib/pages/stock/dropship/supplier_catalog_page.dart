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

class _SupplierCatalogPageState extends State<SupplierCatalogPage> {
  final _search = TextEditingController();
  final _commerce = CommerceService();
  List<CjCatalogProduct> _products = const [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  bool _digitalPaymentsEnabled = false;

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _commerce.searchCjCatalog(
        query: _search.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search CJdropshipping products',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: _loading ? null : () => _load(),
                icon: const Icon(Icons.arrow_forward),
              ),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _load(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              Icon(
                _digitalPaymentsEnabled
                    ? Icons.verified_outlined
                    : Icons.info_outline,
                size: 17,
                color: _digitalPaymentsEnabled ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _digitalPaymentsEnabled
                      ? 'Live supplier products. Delivery is checked automatically for South Africa.'
                      : 'Orders use manual payment for now. Sellers confirm payment before ordering from CJ.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _CatalogMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load CJdropshipping',
        message: _error!,
        action: () => _load(page: _page),
      );
    }
    if (_products.isEmpty) {
      return _CatalogMessage(
        icon: Icons.search_off_outlined,
        title: 'No matching products',
        message: 'Try a simpler product name or a different search.',
        action: () {
          _search.clear();
          _load();
        },
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 100),
      itemCount: _products.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == _products.length) {
          return Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _page > 1 ? () => _load(page: _page - 1) : null,
                  child: const Text('Previous'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('$_page / $_totalPages'),
              ),
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _page < _totalPages ? () => _load(page: _page + 1) : null,
                  child: const Text('Next'),
                ),
              ),
            ],
          );
        }
        return _SupplierProductCard(
          product: _products[index],
          digitalPaymentsEnabled: _digitalPaymentsEnabled,
        );
      },
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
            const Icon(Icons.check_circle, color: Colors.green, size: 56),
            const SizedBox(height: 12),
            const Text(
              'Listing created',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'It is now in your Spaza One products and ready to share.',
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
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _select(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductImage(url: product.image, size: 88),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (product.category.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        product.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Product from ${CurrencyUtil.format(product.estimatedProductCostMinor / 100)}',
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Choose variant & calculate delivery',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
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
    try {
      final details = await _commerce.getCjProduct(widget.product.id);
      if (!mounted) return;
      if (details.variants.isEmpty) {
        setState(() {
          _loadingDetails = false;
          _error = 'This supplier product has no available variants.';
        });
        return;
      }
      setState(() {
        _details = details;
        _variant = details.variants.first;
        _loadingDetails = false;
      });
      await _loadQuote();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingDetails = false;
        _error = commerceErrorMessage(error);
      });
    }
  }

  Future<void> _loadQuote() async {
    final variant = _variant;
    if (variant == null) return;
    setState(() {
      _loadingQuote = true;
      _quote = null;
      _error = null;
    });
    try {
      final quote = await _commerce.quoteCjVariant(
        productId: widget.product.id,
        variantId: variant.id,
      );
      if (!mounted || _variant?.id != variant.id) return;
      setState(() {
        _quote = quote;
        _loadingQuote = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingQuote = false;
        _error = commerceErrorMessage(error);
      });
    }
  }

  Future<void> _create() async {
    final variant = _variant;
    if (variant == null || _quote == null || _markupMinor <= 0) return;
    if (_netMarginMinor < 0) return;
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
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 20, 24, bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductImage(url: widget.product.image, size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CJdropshipping',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.product.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loadingDetails)
            const Center(child: CircularProgressIndicator())
          else if (_details != null) ...[
            DropdownButtonFormField<String>(
              value: _variant?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Product variant',
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
              onChanged: _saving
                  ? null
                  : (id) {
                      final matches =
                          _details!.variants.where((item) => item.id == id);
                      if (matches.isEmpty) return;
                      final variant = matches.first;
                      setState(() => _variant = variant);
                      _loadQuote();
                    },
            ),
            const SizedBox(height: 16),
          ],
          if (_loadingQuote)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text('Checking stock and delivery to South Africa…'),
                ],
              ),
            ),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Text(_error!, style: TextStyle(color: Colors.red.shade800)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadingQuote ? null : _loadQuote,
              child: const Text('Try again'),
            ),
          ],
          if (_quote != null) ...[
            _PriceRow(
              label: 'Supplier product',
              value: CurrencyUtil.format(_quote!.productCostMinor / 100),
            ),
            _PriceRow(
              label: 'Estimated delivery',
              value: CurrencyUtil.format(_quote!.shippingCostMinor / 100),
            ),
            _PriceRow(
              label: 'Estimated landed cost',
              value: CurrencyUtil.format(_quote!.landedCostMinor / 100),
              emphasized: true,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 16),
              child: Text(
                '${_quote!.logisticName}'
                '${_quote!.logisticAging.isEmpty ? '' : ' · ${_quote!.logisticAging} days'}'
                ' · ${_quote!.stock} available',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextField(
              controller: _markup,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*[.,]?\d{0,2}'),
                ),
              ],
              decoration: const InputDecoration(
                labelText: 'Your markup (R)',
                prefixText: 'R ',
                border: OutlineInputBorder(),
                helperText: 'Your markup stays fixed when delivery changes.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),
            _PriceRow(
              label: 'Estimated buyer price',
              value: CurrencyUtil.format(_sellPriceMinor / 100),
              emphasized: true,
            ),
            _PriceRow(
              label: widget.digitalPaymentsEnabled
                  ? 'Estimated Paystack fee'
                  : 'Online payment fee',
              value: '- ${CurrencyUtil.format(_feeMinor / 100)}',
            ),
            _PriceRow(
              label: 'Estimated margin after fee',
              value: CurrencyUtil.format(_netMarginMinor / 100),
              emphasized: true,
            ),
            if (_markupMinor > 0 && _netMarginMinor < 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Increase the markup so it covers the estimated payment fee.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 12),
            if (!widget.digitalPaymentsEnabled) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Buyers will send an order request without paying online. Confirm their manual payment in Orders before placing the CJ order.',
                  style: TextStyle(color: Colors.orange.shade900),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              'The buyer’s address is checked again before payment. The final supplier, delivery, exchange-rate and margin values are stored on the order.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving || _markupMinor <= 0 || _netMarginMinor < 0
                  ? null
                  : _create,
              child: Text(
                _saving ? 'Checking & creating…' : 'Add to my products',
              ),
            ),
          ],
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
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.broken_image_outlined),
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
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
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
            OutlinedButton(onPressed: action, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
