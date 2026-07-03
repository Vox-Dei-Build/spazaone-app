import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/sales/sales_intent_bus.dart';

void main() {
  test('sales intent is consumed once', () {
    final bus = SalesIntentBus.instance;
    bus.consume();

    const intent = SalesIntent(
      section: SalesIntentSection.marketing,
      marketingView: SalesIntentMarketingView.templates,
    );

    bus.set(intent);

    expect(bus.consume(), same(intent));
    expect(bus.consume(), isNull);
  });
}
