int _asInt(Object? value) =>
    value is num ? value.round() : int.tryParse('$value') ?? 0;

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

class CjCatalogPage {
  const CjCatalogPage({
    required this.products,
    required this.page,
    required this.totalPages,
    required this.totalProducts,
    required this.hasMore,
    required this.nextCursor,
    required this.catalogueRefreshing,
    required this.digitalPaymentsEnabled,
    this.totalProductsExact = true,
    this.usableProductsLowerBound = 0,
    this.scanLimited = false,
  });

  final List<CjCatalogProduct> products;
  final int page;
  final int totalPages;
  final int totalProducts;
  final bool hasMore;
  final String nextCursor;
  final bool catalogueRefreshing;
  final bool digitalPaymentsEnabled;
  final bool totalProductsExact;
  final int usableProductsLowerBound;
  final bool scanLimited;

  factory CjCatalogPage.fromJson(Map<String, dynamic> data) => CjCatalogPage(
        products: (data['products'] as List? ?? const [])
            .map((value) => CjCatalogProduct.fromJson(_asMap(value)))
            .where((product) => product.id.isNotEmpty)
            .toList(growable: false),
        page: _asInt(data['page']),
        totalPages: _asInt(data['totalPages']),
        totalProducts: _asInt(data['totalProducts']),
        hasMore: data['hasMore'] == true ||
            _asInt(data['page']) < _asInt(data['totalPages']),
        nextCursor: data['nextCursor']?.toString() ?? '',
        catalogueRefreshing: data['catalogueRefreshing'] == true,
        digitalPaymentsEnabled: data['digitalPaymentsEnabled'] == true,
        // Older Functions responses calculated and exposed a total directly.
        // New bounded scans mark unknown totals explicitly instead of treating
        // stale raw Firestore rows as sellable products.
        totalProductsExact: data.containsKey('totalProductsExact')
            ? data['totalProductsExact'] == true
            : true,
        usableProductsLowerBound: _asInt(data['usableProductsLowerBound']),
        scanLimited: data['scanLimited'] == true,
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
    this.catalogQuoteVersion = '',
    this.saved = false,
    this.availability = 'available',
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
  final String catalogQuoteVersion;
  final bool saved;
  final String availability;

  bool get isAvailable => availability == 'available';

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
        catalogQuoteVersion: data['catalogQuoteVersion']?.toString() ??
            data['deliveryVerifiedAt']?.toString() ??
            '',
        saved: data['saved'] == true,
        availability: data['availability']?.toString() ?? 'available',
      );

  Map<String, dynamic> toJson() => {
        'productId': id,
        'productSku': sku,
        'title': title,
        'image': image,
        'category': category,
        'productCostUsdMinor': productCostUsdMinor,
        'estimatedProductCostMinor': estimatedProductCostMinor,
        'deliverableVariantId': deliverableVariantId,
        'estimatedDeliveryCostMinor': estimatedDeliveryCostMinor,
        'estimatedLandedCostMinor': estimatedLandedCostMinor,
        'logisticAging': logisticAging,
        'deliveryVerifiedAt': deliveryVerifiedAt,
        'catalogQuoteVersion': catalogQuoteVersion,
        'saved': saved,
        'availability': availability,
      };

  CjCatalogProduct copyWith({
    String? availability,
    bool? saved,
  }) =>
      CjCatalogProduct(
        id: id,
        sku: sku,
        title: title,
        image: image,
        category: category,
        productCostUsdMinor: productCostUsdMinor,
        estimatedProductCostMinor: estimatedProductCostMinor,
        deliverableVariantId: deliverableVariantId,
        estimatedDeliveryCostMinor: estimatedDeliveryCostMinor,
        estimatedLandedCostMinor: estimatedLandedCostMinor,
        logisticAging: logisticAging,
        deliveryVerifiedAt: deliveryVerifiedAt,
        catalogQuoteVersion: catalogQuoteVersion,
        saved: saved ?? this.saved,
        availability: availability ?? this.availability,
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
    required this.recommendedVariantId,
    required this.recommendedQuote,
  });

  final String id;
  final String sku;
  final String title;
  final String description;
  final List<String> images;
  final String category;
  final List<CjVariant> variants;
  final String recommendedVariantId;
  final CjLandedQuote? recommendedQuote;

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
        recommendedVariantId: data['recommendedVariantId']?.toString() ?? '',
        recommendedQuote: data['recommendedQuote'] is Map
            ? CjLandedQuote.fromJson(_asMap(data['recommendedQuote']))
            : null,
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

enum CjListingEstimateSource { recommendedQuote, catalogSnapshot }

class CjListingEstimate {
  const CjListingEstimate({
    required this.variant,
    required this.quote,
    required this.source,
  });

  final CjVariant variant;
  final CjLandedQuote quote;
  final CjListingEstimateSource source;

  bool get usesCatalogSnapshot =>
      source == CjListingEstimateSource.catalogSnapshot;
}

CjVariant? _variantWithId(List<CjVariant> variants, String id) {
  for (final variant in variants) {
    if (variant.id == id) return variant;
  }
  return null;
}

/// Hard safety ceiling for a catalogue delivery quote.
///
/// The worker normally refreshes positive quotes every 72 hours. Seven days
/// provides a bounded grace period for a delayed worker without allowing an
/// indefinitely old stock/freight result to be presented as verified.
const Duration cjCatalogSnapshotMaximumAge = Duration(days: 7);

bool isCjCatalogSnapshotFresh(
  String deliveryVerifiedAt, {
  DateTime? now,
}) {
  final verifiedAt = DateTime.tryParse(deliveryVerifiedAt)?.toUtc();
  final current = (now ?? DateTime.now()).toUtc();
  if (verifiedAt == null || verifiedAt.isAfter(current)) return false;
  return current.difference(verifiedAt) <= cjCatalogSnapshotMaximumAge;
}

/// Builds the listing estimate already verified for a catalogue card.
///
/// The catalogue endpoint returns only products backed by a positive cached
/// stock and South Africa freight quote. Opening a product may fetch richer
/// details (such as the option label), but that second request is not an
/// availability check and must not invalidate the verified card when it is
/// slow or temporarily unavailable. Listing creation still validates this
/// exact product/variant against the server cache before writing anything.
CjListingEstimate? resolveCjCatalogSnapshotEstimate({
  required CjCatalogProduct catalogProduct,
  CjVariant? verifiedVariant,
  DateTime? now,
}) {
  final cachedVariantId = catalogProduct.deliverableVariantId;
  final usableCatalogSnapshot = catalogProduct.id.isNotEmpty &&
      cachedVariantId.isNotEmpty &&
      catalogProduct.estimatedProductCostMinor > 0 &&
      catalogProduct.estimatedDeliveryCostMinor >= 0 &&
      catalogProduct.estimatedLandedCostMinor ==
          catalogProduct.estimatedProductCostMinor +
              catalogProduct.estimatedDeliveryCostMinor &&
      isCjCatalogSnapshotFresh(
        catalogProduct.deliveryVerifiedAt,
        now: now,
      );
  if (!usableCatalogSnapshot) return null;

  final candidate = verifiedVariant;
  final cachedVariant = candidate != null &&
          candidate.id == cachedVariantId &&
          (candidate.productId.isEmpty ||
              candidate.productId == catalogProduct.id)
      ? candidate
      : CjVariant(
          id: cachedVariantId,
          productId: catalogProduct.id,
          sku: '',
          name: 'Recommended option',
          option: '',
          image: catalogProduct.image,
          productCostUsdMinor: catalogProduct.productCostUsdMinor,
          estimatedProductCostMinor: catalogProduct.estimatedProductCostMinor,
        );
  return CjListingEstimate(
    variant: cachedVariant,
    quote: CjLandedQuote(
      variant: cachedVariant,
      originCountryCode: '',
      stock: 0,
      logisticName: '',
      logisticAging: catalogProduct.logisticAging,
      productCostMinor: catalogProduct.estimatedProductCostMinor,
      shippingCostMinor: catalogProduct.estimatedDeliveryCostMinor,
      landedCostMinor: catalogProduct.estimatedLandedCostMinor,
      fxRateMicros: 0,
      fxBufferBps: 0,
    ),
    source: CjListingEstimateSource.catalogSnapshot,
  );
}

/// Opens a product already approved by the server's catalogue search.
///
/// Freshness is deliberately not checked against the phone clock. The search
/// endpoint applies the freshness gate using server time, and listing creation
/// revalidates the quote version. The app only checks that the received price
/// and selected option are internally consistent enough to render.
CjListingEstimate? resolveServerApprovedCatalogEstimate({
  required CjCatalogProduct catalogProduct,
}) {
  final cachedVariantId = catalogProduct.deliverableVariantId;
  final structurallyUsable = catalogProduct.id.isNotEmpty &&
      cachedVariantId.isNotEmpty &&
      catalogProduct.estimatedProductCostMinor > 0 &&
      catalogProduct.estimatedDeliveryCostMinor >= 0 &&
      catalogProduct.estimatedLandedCostMinor ==
          catalogProduct.estimatedProductCostMinor +
              catalogProduct.estimatedDeliveryCostMinor;
  if (!structurallyUsable) return null;

  final variant = CjVariant(
    id: cachedVariantId,
    productId: catalogProduct.id,
    sku: '',
    name: 'Recommended option',
    option: '',
    image: catalogProduct.image,
    productCostUsdMinor: catalogProduct.productCostUsdMinor,
    estimatedProductCostMinor: catalogProduct.estimatedProductCostMinor,
  );
  return CjListingEstimate(
    variant: variant,
    quote: CjLandedQuote(
      variant: variant,
      originCountryCode: '',
      stock: 0,
      logisticName: '',
      logisticAging: catalogProduct.logisticAging,
      productCostMinor: catalogProduct.estimatedProductCostMinor,
      shippingCostMinor: catalogProduct.estimatedDeliveryCostMinor,
      landedCostMinor: catalogProduct.estimatedLandedCostMinor,
      fxRateMicros: 0,
      fxBufferBps: 0,
    ),
    source: CjListingEstimateSource.catalogSnapshot,
  );
}

/// Resolves the single delivery-verified option shown when creating a listing.
///
/// Newer servers include a current recommended quote. During a rolling backend
/// release, older servers return only product details; in that case the
/// catalogue card already contains the last verified South Africa variant and
/// cost snapshot. Using that snapshot avoids a second supplier request merely
/// for opening the sheet. Listing creation remains server-priced and is the
/// authoritative availability check.
CjListingEstimate? resolveCjListingEstimate({
  required CjCatalogProduct catalogProduct,
  required CjProductDetails details,
  DateTime? now,
}) {
  if (details.id.isEmpty || details.id != catalogProduct.id) return null;
  if (!isCjCatalogSnapshotFresh(
    catalogProduct.deliveryVerifiedAt,
    now: now,
  )) {
    return null;
  }
  final recommendedQuote = details.recommendedQuote;
  final recommendedVariantId = recommendedQuote?.variant.id ?? '';
  final recommendedProductId = recommendedQuote?.variant.productId ?? '';
  final usableRecommendedQuote = recommendedQuote != null &&
      recommendedVariantId.isNotEmpty &&
      recommendedQuote.productCostMinor > 0 &&
      recommendedQuote.shippingCostMinor >= 0 &&
      recommendedQuote.landedCostMinor > 0 &&
      (recommendedProductId.isEmpty ||
          recommendedProductId == catalogProduct.id);
  if (usableRecommendedQuote) {
    return CjListingEstimate(
      variant: _variantWithId(details.variants, recommendedVariantId) ??
          recommendedQuote.variant,
      quote: recommendedQuote,
      source: CjListingEstimateSource.recommendedQuote,
    );
  }

  return resolveCjCatalogSnapshotEstimate(
    catalogProduct: catalogProduct,
    now: now,
    verifiedVariant: _variantWithId(
      details.variants,
      catalogProduct.deliverableVariantId,
    ),
  );
}
