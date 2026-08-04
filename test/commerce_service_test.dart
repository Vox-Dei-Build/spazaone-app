import 'package:flutter_test/flutter_test.dart';
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
}
