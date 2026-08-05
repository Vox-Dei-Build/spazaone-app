import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/commerce/cj_supplier_product.dart';
import 'package:pasella/services/commerce_service.dart';

void main() {
  test('debug catalogue routing stays isolated from stable callables', () {
    expect(
      dropshipCallableName('searchCjSupplierCatalog', useV2: false),
      'searchCjSupplierCatalog',
    );
    expect(
      dropshipCallableName('searchCjSupplierCatalog', useV2: true),
      'searchCjSupplierCatalogV2',
    );
    expect(
      dropshipCallableName('createDropshipListing', useV2: true),
      'createDropshipListingV2',
    );
  });

  CjCatalogProduct catalogProduct({
    String deliverableVariantId = 'variant-za',
    int productCostMinor = 10000,
    int deliveryCostMinor = 5000,
    int landedCostMinor = 15000,
  }) {
    return CjCatalogProduct.fromJson({
      'productId': 'product-1',
      'productSku': 'LAMP-1',
      'title': 'Lamp',
      'image': 'https://example.com/lamp.jpg',
      'productCostUsdMinor': 600,
      'estimatedProductCostMinor': productCostMinor,
      'deliverableVariantId': deliverableVariantId,
      'estimatedDeliveryCostMinor': deliveryCostMinor,
      'estimatedLandedCostMinor': landedCostMinor,
      'logisticAging': '8-14 days',
      'deliveryVerifiedAt': '2026-08-05T10:00:00.000Z',
    });
  }

  test('catalog page keeps background-refresh and cursor metadata', () {
    final page = CjCatalogPage.fromJson({
      'products': const [],
      'page': 1,
      'totalPages': 3,
      'hasMore': true,
      'nextCursor': 'cj_product_11',
      'catalogueRefreshing': true,
      'digitalPaymentsEnabled': false,
    });

    expect(page.hasMore, isTrue);
    expect(page.nextCursor, 'cj_product_11');
    expect(page.catalogueRefreshing, isTrue);
  });

  test('supplier errors never expose provider or connection details', () {
    for (final message in [
      'CJ dropshipping could not be reached. Please try again.',
      'The supplier network could not be reached.',
      'SocketException: failed host lookup',
    ]) {
      final friendly = friendlyCommerceErrorMessage(message);
      expect(friendly, startsWith('Spaza One could not refresh'));
      expect(friendly.toLowerCase(), isNot(contains('cj')));
      expect(friendly.toLowerCase(), isNot(contains('network')));
      expect(friendly.toLowerCase(), isNot(contains('connection')));
    }
  });

  test('specific actionable supplier messages remain intact', () {
    expect(
      friendlyCommerceErrorMessage(
        'That variant is currently out of stock.',
      ),
      'That variant is currently out of stock.',
    );
  });

  test('product details retain the server-verified variant and quote', () {
    final details = CjProductDetails.fromJson({
      'productId': 'product-1',
      'title': 'Lamp',
      'recommendedVariantId': 'variant-za',
      'variants': [
        {
          'variantId': 'variant-za',
          'productId': 'product-1',
          'option': 'Black',
        },
      ],
      'recommendedQuote': {
        'variant': {
          'variantId': 'variant-za',
          'productId': 'product-1',
          'option': 'Black',
        },
        'stock': 42,
        'productCostMinor': 10000,
        'shippingCostMinor': 5000,
        'landedCostMinor': 15000,
        'fx': {'rateMicros': 16440800, 'bufferBps': 300},
      },
    });

    expect(details.recommendedVariantId, 'variant-za');
    expect(details.recommendedQuote?.variant.id, 'variant-za');
    expect(details.recommendedQuote?.landedCostMinor, 15000);
  });

  test(
      'old product response uses the catalog snapshot without a live quote dependency',
      () {
    final details = CjProductDetails.fromJson({
      'productId': 'product-1',
      'title': 'Lamp',
      'variants': [
        {
          'variantId': 'variant-other',
          'productId': 'product-1',
          'option': 'White',
        },
        {
          'variantId': 'variant-za',
          'productId': 'product-1',
          'option': 'Black',
        },
      ],
    });

    expect(details.recommendedVariantId, isEmpty);
    expect(details.recommendedQuote, isNull);

    final estimate = resolveCjListingEstimate(
      catalogProduct: catalogProduct(),
      details: details,
    );

    expect(estimate, isNotNull);
    expect(estimate!.usesCatalogSnapshot, isTrue);
    expect(estimate.variant.id, 'variant-za');
    expect(estimate.variant.label, 'Black');
    expect(estimate.quote.productCostMinor, 10000);
    expect(estimate.quote.shippingCostMinor, 5000);
    expect(estimate.quote.landedCostMinor, 15000);
  });

  test('new product response prefers its recommended quote', () {
    final details = CjProductDetails.fromJson({
      'productId': 'product-1',
      'title': 'Lamp',
      'recommendedVariantId': 'variant-current',
      'variants': [
        {
          'variantId': 'variant-za',
          'productId': 'product-1',
          'option': 'Black',
        },
        {
          'variantId': 'variant-current',
          'productId': 'product-1',
          'option': 'Green',
        },
      ],
      'recommendedQuote': {
        'variant': {
          'variantId': 'variant-current',
          'productId': 'product-1',
          'option': 'Green',
        },
        'stock': 12,
        'productCostMinor': 11000,
        'shippingCostMinor': 6000,
        'landedCostMinor': 17000,
        'fx': {'rateMicros': 16440800, 'bufferBps': 300},
      },
    });

    final estimate = resolveCjListingEstimate(
      catalogProduct: catalogProduct(),
      details: details,
    );

    expect(estimate, isNotNull);
    expect(estimate!.source, CjListingEstimateSource.recommendedQuote);
    expect(estimate.variant.id, 'variant-current');
    expect(estimate.quote.landedCostMinor, 17000);
    expect(estimate.quote.stock, 12);
  });

  test('unchecked alternate variants are not substituted for cached option',
      () {
    final details = CjProductDetails.fromJson({
      'productId': 'product-1',
      'title': 'Lamp',
      'variants': [
        {
          'variantId': 'variant-other',
          'productId': 'product-1',
          'option': 'White',
        },
      ],
    });

    final estimate = resolveCjListingEstimate(
      catalogProduct: catalogProduct(),
      details: details,
    );

    expect(estimate, isNotNull);
    expect(estimate!.variant.id, 'variant-za');
    expect(estimate.variant.label, 'Recommended option');
    expect(estimate.variant.id, isNot('variant-other'));
  });

  test('invalid recommendation falls back only to a positive catalog snapshot',
      () {
    final details = CjProductDetails.fromJson({
      'productId': 'product-1',
      'title': 'Lamp',
      'recommendedQuote': {
        'variant': {
          'variantId': 'variant-wrong-product',
          'productId': 'product-2',
        },
        'productCostMinor': 100,
        'shippingCostMinor': 100,
        'landedCostMinor': 200,
      },
    });

    final fallback = resolveCjListingEstimate(
      catalogProduct: catalogProduct(),
      details: details,
    );
    final unavailable = resolveCjListingEstimate(
      catalogProduct: catalogProduct(landedCostMinor: 0),
      details: details,
    );

    expect(fallback?.source, CjListingEstimateSource.catalogSnapshot);
    expect(unavailable, isNull);
  });
}
