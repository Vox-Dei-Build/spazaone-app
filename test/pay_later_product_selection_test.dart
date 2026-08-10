import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/providers/transactional_view_model.dart';

void main() {
  test('manual transactions exclude dropshipping listings', () {
    final stockedProduct = Product(
      id: 'stocked-product',
      name: 'Stocked product',
      quantity: 4,
    );
    final dropshipProduct = Product(
      id: 'dropship-product',
      name: 'Dropship product',
      quantity: 99,
      isDropshipListing: true,
    );

    final selectable = selectableManualTransactionProducts([
      dropshipProduct,
      stockedProduct,
    ]);

    expect(selectable, [same(stockedProduct)]);
    expect(selectable, isNot(contains(same(dropshipProduct))));
  });
}
