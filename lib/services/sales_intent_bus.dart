/// Process-singleton "pending intent" bus for the Sales page.
///
/// The Sales page hosts two top-level tabs (Sales, Marketing). When another
/// surface — e.g. the
/// merchant setup card — wants to route the merchant to a specific
/// view of Sales, it stashes an intent here and switches the bottom
/// navigation index to Sales. `SalesPage.initState` then takes the
/// intent and configures its tab controller before the first frame
/// paints, so the merchant lands on the requested view directly rather
/// than seeing the default Sales tab flash first.
///
/// The bus lives in `lib/services/` alongside
/// `ActivationNudgeIntentBus`, which does the same for FCM deep-link
/// intents. Both use the same `stash`/`take` verb pair so callers can
/// swap between them without relearning the API.
library;

import 'package:flutter/foundation.dart';

/// The legacy marketing destination requested by a caller.
///
/// Sales now has one product-first Marketing overview, so both values land on
/// the same screen. Keeping the values preserves compatibility with older
/// entry points while advanced template management moves out of the everyday
/// campaign journey.
enum SalesIntentMarketingView { promotions, templates }

/// A single request to open a specific view of Sales.
///
/// Only marketing intents exist today. The bus deliberately has no
/// "sales" variant: nothing needs to route _to_ the Sales tab
/// explicitly, and the default when there is no pending intent already
/// lands the merchant on Sales.
class SalesIntent {
  const SalesIntent.marketing({
    this.marketingView = SalesIntentMarketingView.promotions,
  });

  final SalesIntentMarketingView marketingView;
}

class SalesIntentBus extends ChangeNotifier {
  SalesIntentBus._();
  static final SalesIntentBus instance = SalesIntentBus._();

  SalesIntent? _pending;

  /// Stashes an intent for the next `SalesPage.initState` to consume.
  /// Overwrites any previous unconsumed intent.
  void stash(SalesIntent intent) {
    _pending = intent;
    // SalesPage is kept alive by the app's bottom navigation. Notify it as
    // well as retaining the intent for a page that has not mounted yet.
    notifyListeners();
  }

  /// Reads and clears the pending intent. Returns `null` if none is
  /// stashed.
  SalesIntent? take() {
    final value = _pending;
    _pending = null;
    return value;
  }
}
