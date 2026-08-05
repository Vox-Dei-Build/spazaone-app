int _asInt(Object? value) =>
    value is num ? value.round() : int.tryParse('$value') ?? 0;

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

class CjCatalogPage {
  const CjCatalogPage({
    required this.products,
    required this.page,
    required this.totalPages,
    required this.digitalPaymentsEnabled,
  });

  final List<CjCatalogProduct> products;
  final int page;
  final int totalPages;
  final bool digitalPaymentsEnabled;

  factory CjCatalogPage.fromJson(Map<String, dynamic> data) => CjCatalogPage(
        products: (data['products'] as List? ?? const [])
            .map((value) => CjCatalogProduct.fromJson(_asMap(value)))
            .where((product) => product.id.isNotEmpty)
            .toList(growable: false),
        page: _asInt(data['page']),
        totalPages: _asInt(data['totalPages']),
        digitalPaymentsEnabled: data['digitalPaymentsEnabled'] == true,
      );
}

class CjCatalogProduct {
  const CjCatalogProduct({
    required this.id,
    required this.sku,
    required this.title,
    required this.image,
    required this.category,
    required this.productCostUsdMinor,
    required this.estimatedProductCostMinor,
    required this.deliverableVariantId,
    required this.estimatedDeliveryCostMinor,
    required this.estimatedLandedCostMinor,
    required this.logisticAging,
    required this.deliveryVerifiedAt,
  });

  final String id;
  final String sku;
  final String title;
  final String image;
  final String category;
  final int productCostUsdMinor;
  final int estimatedProductCostMinor;
  final String deliverableVariantId;
  final int estimatedDeliveryCostMinor;
  final int estimatedLandedCostMinor;
  final String logisticAging;
  final String deliveryVerifiedAt;

  factory CjCatalogProduct.fromJson(Map<String, dynamic> data) =>
      CjCatalogProduct(
        id: data['productId']?.toString() ?? '',
        sku: data['productSku']?.toString() ?? '',
        title: data['title']?.toString() ?? 'Supplier product',
        image: data['image']?.toString() ?? '',
        category: data['category']?.toString() ?? '',
        productCostUsdMinor: _asInt(data['productCostUsdMinor']),
        estimatedProductCostMinor: _asInt(data['estimatedProductCostMinor']),
        deliverableVariantId: data['deliverableVariantId']?.toString() ?? '',
        estimatedDeliveryCostMinor: _asInt(data['estimatedDeliveryCostMinor']),
        estimatedLandedCostMinor: _asInt(data['estimatedLandedCostMinor']),
        logisticAging: data['logisticAging']?.toString() ?? '',
        deliveryVerifiedAt: data['deliveryVerifiedAt']?.toString() ?? '',
      );
}

class CjProductDetails {
  const CjProductDetails({
    required this.id,
    required this.sku,
    required this.title,
    required this.description,
    required this.images,
    required this.category,
    required this.variants,
  });

  final String id;
  final String sku;
  final String title;
  final String description;
  final List<String> images;
  final String category;
  final List<CjVariant> variants;

  factory CjProductDetails.fromJson(Map<String, dynamic> data) =>
      CjProductDetails(
        id: data['productId']?.toString() ?? '',
        sku: data['productSku']?.toString() ?? '',
        title: data['title']?.toString() ?? 'Supplier product',
        description: data['description']?.toString() ?? '',
        images: (data['images'] as List? ?? const [])
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toList(growable: false),
        category: data['category']?.toString() ?? '',
        variants: (data['variants'] as List? ?? const [])
            .map((value) => CjVariant.fromJson(_asMap(value)))
            .where((variant) => variant.id.isNotEmpty)
            .toList(growable: false),
      );
}

class CjVariant {
  const CjVariant({
    required this.id,
    required this.productId,
    required this.sku,
    required this.name,
    required this.option,
    required this.image,
    required this.productCostUsdMinor,
    required this.estimatedProductCostMinor,
  });

  final String id;
  final String productId;
  final String sku;
  final String name;
  final String option;
  final String image;
  final int productCostUsdMinor;
  final int estimatedProductCostMinor;

  String get label {
    if (option.isNotEmpty) return option;
    if (name.isNotEmpty) return name;
    return sku;
  }

  factory CjVariant.fromJson(Map<String, dynamic> data) => CjVariant(
        id: data['variantId']?.toString() ?? '',
        productId: data['productId']?.toString() ?? '',
        sku: data['sku']?.toString() ?? '',
        name: data['name']?.toString() ?? '',
        option: data['option']?.toString() ?? '',
        image: data['image']?.toString() ?? '',
        productCostUsdMinor: _asInt(data['productCostUsdMinor']),
        estimatedProductCostMinor: _asInt(data['estimatedProductCostMinor']),
      );
}

class CjLandedQuote {
  const CjLandedQuote({
    required this.variant,
    required this.originCountryCode,
    required this.stock,
    required this.logisticName,
    required this.logisticAging,
    required this.productCostMinor,
    required this.shippingCostMinor,
    required this.landedCostMinor,
    required this.fxRateMicros,
    required this.fxBufferBps,
  });

  final CjVariant variant;
  final String originCountryCode;
  final int stock;
  final String logisticName;
  final String logisticAging;
  final int productCostMinor;
  final int shippingCostMinor;
  final int landedCostMinor;
  final int fxRateMicros;
  final int fxBufferBps;

  factory CjLandedQuote.fromJson(Map<String, dynamic> data) {
    final fx = _asMap(data['fx']);
    return CjLandedQuote(
      variant: CjVariant.fromJson(_asMap(data['variant'])),
      originCountryCode: data['originCountryCode']?.toString() ?? '',
      stock: _asInt(data['stock']),
      logisticName: data['logisticName']?.toString() ?? '',
      logisticAging: data['logisticAging']?.toString() ?? '',
      productCostMinor: _asInt(data['productCostMinor']),
      shippingCostMinor: _asInt(data['shippingCostMinor']),
      landedCostMinor: _asInt(data['landedCostMinor']),
      fxRateMicros: _asInt(fx['rateMicros']),
      fxBufferBps: _asInt(fx['bufferBps']),
    );
  }
}
