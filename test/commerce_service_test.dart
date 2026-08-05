import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/commerce/cj_supplier_product.dart';
import 'package:pasella/services/commerce_service.dart';

void main() {
  test('dropship sharing opens the bot with shop and product context', () {
    final orderingUrl = CommerceService.buildProductOrderingUrl(
      baseUrl: Uri.parse(
        'https://wa.me/27640000000?text=shop%20OLD&source=spaza-one',
      ),
      code: 'AB12CD',
      title: 'Portable Mini Blender',
    );

    final uri = Uri.parse(orderingUrl);
    expect(uri.host, 'wa.me');
    expect(uri.queryParameters['source'], 'spaza-one');
    expect(
      uri.queryParameters['text'],
      'shop AB12CD order 1 Portable Mini Blender',
    );
    expect(
      CommerceService.shareMessage(
        title: 'Portable Mini Blender',
        orderingUrl: orderingUrl,
      ),
      contains('Order Portable Mini Blender from Spaza One on WhatsApp:'),
    );
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
}
