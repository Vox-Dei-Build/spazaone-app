library;

enum SalesIntentSection { sales, marketing }

enum SalesIntentMarketingView { promotions, templates }

class SalesIntent {
  final SalesIntentSection section;
  final SalesIntentMarketingView marketingView;

  const SalesIntent({
    required this.section,
    this.marketingView = SalesIntentMarketingView.promotions,
  });
}

class SalesIntentBus {
  SalesIntentBus._();
  static final SalesIntentBus instance = SalesIntentBus._();

  SalesIntent? _pending;

  void set(SalesIntent intent) {
    _pending = intent;
  }

  SalesIntent? consume() {
    final pending = _pending;
    _pending = null;
    return pending;
  }
}
