import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/sales_intent_bus.dart';

void main() {
  test('marketing intent is taken exactly once', () {
    final bus = SalesIntentBus.instance;
    // Clear any stashed intent from prior tests / hot-restart.
    bus.take();

    const intent = SalesIntent.marketing(
      marketingView: SalesIntentMarketingView.templates,
    );

    bus.stash(intent);

    expect(bus.take(), same(intent));
    expect(bus.take(), isNull);
  });

  test('stash overwrites any previous unconsumed intent', () {
    final bus = SalesIntentBus.instance;
    bus.take();

    bus.stash(const SalesIntent.marketing());
    bus.stash(
      const SalesIntent.marketing(
        marketingView: SalesIntentMarketingView.templates,
      ),
    );

    final taken = bus.take();
    expect(taken?.marketingView, SalesIntentMarketingView.templates);
    expect(bus.take(), isNull);
  });

  test('SalesIntent.marketing defaults to promotions view', () {
    const intent = SalesIntent.marketing();
    expect(intent.marketingView, SalesIntentMarketingView.promotions);
  });
}
