import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/pages/promote/utils/template_status.dart';

/// PAS-UX-02 / PAS-UX-09: first-session aha checklist.
///
/// **Deprecated (PAS-UX-rel).** Superseded by
/// [MerchantSetupCard] in
/// `lib/shared/widgets/onboarding/merchant_setup_card.dart`, which
/// covers a superset of these four steps (customer, product, WhatsApp
/// listing, ordering link, banking, template), scrolls with the
/// Customers list rather than consuming persistent Dashboard chrome,
/// and consumes state from a single [Stream<MerchantSetupState>]
/// instead of four nested subscriptions. This widget is no longer
/// mounted anywhere and is retained only so its Hive-persistence
/// approach and auto-tick logic can be referenced if we ever need to
/// re-introduce a per-screen banner. Do not use in new code.
///
/// The audit found that a new merchant landing in the app has no
/// scaffolded path through the four actions that produce the first
/// believable "aha" moment:
///
///   1. Add a customer.
///   2. Add a product to your stock list when stock detail is needed.
///   3. Record your first sale.
///   4. Get a WhatsApp template approved (so you can run a promotion).
///
/// Until each step is done, the merchant has no concrete reason to
/// trust the app, no data on any screen, and no way to evaluate
/// whether the product fits their workflow. Empty-state CTAs help
/// (PAS-UX-04 added them on Stock, PAS-UX-09 added them on
/// Customers), but they're per-screen and the merchant has to
/// discover each one.
///
/// This widget surfaces all four steps as a single dismissible
/// banner on the Dashboard scaffold (PAS-UX-09 moved it here from
/// LedgerPage so it's visible across all three primary tabs —
/// Customers, Products, Sales — instead of only on the default
/// landing tab). Each tile:
///
///   - links to the screen that completes it,
///   - **auto-completes from real Firestore data** (PAS-UX-09):
///       * Add Product   → users/{uid}/products has any doc
///       * Add Customer  → users/{uid}/customers has any doc
///       * Record Sale   → users/{uid}/sales has any doc
///       * Approve WA Template → messagingTemplates where userId=uid
///         contains a doc with `channels.whatsapp.approvalStatus`
///         resolving to TemplateStatus.approved (uses the canonical
///         resolver in lib/pages/promote/utils/template_status.dart
///         so this widget stays in sync with how the rest of the app
///         reads approval).
///   - can still be manually ticked off so a merchant who completed
///     an action through a backend / console path can mark it
///     resolved without polluting the UI.
///
/// The auto-tick streams are subscribed in initState and disposed in
/// dispose. Each is `.limit(1)` so reads stay cheap even on accounts
/// with thousands of customers/sales/products. The persisted Hive
/// state is OR'd with the live data signal — once *either* signal
/// flips true, the item is done.
///
/// State key in Hive `appBox`:
///   `onboarding_checklist:<userId>` -> Map<String, bool>
/// The banner is hidden when:
///   - the user has explicitly dismissed it, OR
///   - at least three of the four items are marked done.
///
/// Hiding at 3/4 keeps the checklist focused on early activation.
/// Once a merchant has completed most of the setup, the banner stops
/// competing with the actual working surface.
///
/// Out of scope (deferred, see PAS-UX-02 audit notes):
///
///   - Seeding pre-approved starter templates on registration: that
///     requires a backend approval-bypass for seeded templates, plus
///     Twilio template-id reservation. Tracked as a backend item.
///   - Empty-state CTAs across Sales, Orders: PAS-UX-04 established
///     the pattern on Stock, PAS-UX-09 added Customers; the other
///     two surfaces should follow but are tracked separately.
@Deprecated(
  'Use MerchantSetupCard from '
  'package:pasella/shared/widgets/onboarding/merchant_setup_card.dart '
  'instead. This class is no longer mounted and will be removed once '
  'no one references its Hive-persistence approach for reference.',
)
class OnboardingChecklist extends StatefulWidget {
  const OnboardingChecklist({
    super.key,
    required this.userId,
    required this.onAddProduct,
    required this.onAddCustomer,
    required this.onRecordSale,
    required this.onApproveTemplate,
  });

  final String userId;
  final VoidCallback onAddProduct;
  final VoidCallback onAddCustomer;
  final VoidCallback onRecordSale;
  final VoidCallback onApproveTemplate;

  @override
  State<OnboardingChecklist> createState() => _OnboardingChecklistState();
}

class _OnboardingChecklistState
    // ignore: deprecated_member_use_from_same_package
    extends State<OnboardingChecklist> {
  static const _boxName = 'appBox';
  static const _dismissedSuffix = ':dismissed';

  static const _itemAddProduct = 'add_product';
  static const _itemAddCustomer = 'add_customer';
  static const _itemRecordSale = 'record_sale';
  static const _itemApproveTemplate = 'approve_template';

  late final String _stateKey = 'onboarding_checklist:${widget.userId}';
  late final String _dismissedKey = '$_stateKey$_dismissedSuffix';

  late Map<String, bool> _state;
  bool _dismissed = false;

  // PAS-UX-09: live data-derived completion. Each flag flips true
  // when its underlying Firestore collection produces at least one
  // matching document. The displayed "done" state for each item is
  // (_state[key] || _autoFlag) so manual ticks and data signals are
  // both honoured — whichever fires first wins.
  bool _autoAddProduct = false;
  bool _autoAddCustomer = false;
  bool _autoRecordSale = false;
  bool _autoApproveTemplate = false;

  StreamSubscription<QuerySnapshot>? _productsSub;
  StreamSubscription<QuerySnapshot>? _customersSub;
  StreamSubscription<QuerySnapshot>? _salesSub;
  StreamSubscription<QuerySnapshot>? _templatesSub;

  @override
  void initState() {
    super.initState();
    _loadState();
    _subscribeToDataSignals();
  }

  @override
  void dispose() {
    _productsSub?.cancel();
    _customersSub?.cancel();
    _salesSub?.cancel();
    _templatesSub?.cancel();
    super.dispose();
  }

  /// PAS-UX-09: cheap `.limit(1)` listeners on each onboarding signal.
  /// We don't care about counts or contents — just whether at least
  /// one doc exists. Once the flag flips true we keep the
  /// subscription open (the user can delete the last record, in which
  /// case the item should un-tick — that's the right UX, and the
  /// stream cost is one doc per merchant per category).
  void _subscribeToDataSignals() {
    if (widget.userId.isEmpty) return;

    final firestore = FirebaseFirestore.instance;
    final userScope = firestore.collection('users').doc(widget.userId);

    void handleSignalError(String key, Object error, StackTrace stackTrace) {
      // PAS-UX-09 follow-up: this checklist now mounts at the shared
      // Dashboard shell level, above Customers / Reports / Products.
      // A Firestore permission/query failure here must never blank the
      // whole surface. Treat the signal as unavailable and keep the
      // checklist interactive instead of crashing the page.
      debugPrint('[OnboardingChecklist] $key signal failed: $error');
    }

    _productsSub = userScope.collection('products').limit(1).snapshots().listen(
      (snap) {
        if (!mounted) return;
        final exists = snap.docs.isNotEmpty;
        if (exists != _autoAddProduct) {
          setState(() => _autoAddProduct = exists);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        handleSignalError('products', error, stackTrace);
      },
    );

    _customersSub =
        userScope.collection('customers').limit(1).snapshots().listen(
      (snap) {
        if (!mounted) return;
        final exists = snap.docs.isNotEmpty;
        if (exists != _autoAddCustomer) {
          setState(() => _autoAddCustomer = exists);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        handleSignalError('customers', error, stackTrace);
      },
    );

    _salesSub = userScope.collection('sales').limit(1).snapshots().listen(
      (snap) {
        if (!mounted) return;
        final exists = snap.docs.isNotEmpty;
        if (exists != _autoRecordSale) {
          setState(() => _autoRecordSale = exists);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        handleSignalError('sales', error, stackTrace);
      },
    );

    // Templates live in a top-level `messagingTemplates` collection
    // scoped by `userId`. Approval status is a nested field that the
    // app reads via `templateStatusOf()` (lib/pages/promote/utils/
    // template_status.dart) — reuse that resolver so this widget
    // can't drift from how the rest of the app interprets the doc.
    // Cap the listener at the first 10 templates so a power-user
    // merchant with hundreds of templates doesn't trigger a giant
    // snapshot just to answer "have you got one approved yet".
    _templatesSub = firestore
        .collection('messagingTemplates')
        .where('userId', isEqualTo: widget.userId)
        .limit(10)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        final anyApproved = snap.docs.any((doc) {
          final data = doc.data();
          return templateStatusOf(data) == TemplateStatus.approved;
        });
        if (anyApproved != _autoApproveTemplate) {
          setState(() => _autoApproveTemplate = anyApproved);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        handleSignalError('messagingTemplates', error, stackTrace);
      },
    );
  }

  void _loadState() {
    final box = Hive.box(_boxName);
    final raw = box.get(_stateKey);
    _state = <String, bool>{
      _itemAddProduct: false,
      _itemAddCustomer: false,
      _itemRecordSale: false,
      _itemApproveTemplate: false,
    };
    if (raw is Map) {
      for (final entry in raw.entries) {
        final k = entry.key;
        final v = entry.value;
        if (k is String && v is bool && _state.containsKey(k)) {
          _state[k] = v;
        }
      }
    }
    _dismissed = box.get(_dismissedKey, defaultValue: false) as bool;
  }

  Future<void> _persist() async {
    final box = Hive.box(_boxName);
    await box.put(_stateKey, _state);
  }

  Future<void> _dismiss() async {
    final box = Hive.box(_boxName);
    await box.put(_dismissedKey, true);
    setState(() => _dismissed = true);
  }

  void _toggle(String key, bool value) {
    setState(() => _state[key] = value);
    _persist();
  }

  /// PAS-UX-09: returns true when either the persisted manual state
  /// or the live data signal says the item is complete. This is the
  /// source of truth for the checkbox display and the completed
  /// count.
  bool _isDone(String key) {
    if (_state[key] == true) return true;
    switch (key) {
      case _itemAddProduct:
        return _autoAddProduct;
      case _itemAddCustomer:
        return _autoAddCustomer;
      case _itemRecordSale:
        return _autoRecordSale;
      case _itemApproveTemplate:
        return _autoApproveTemplate;
    }
    return false;
  }

  int get _completedCount => [
        _itemAddCustomer,
        _itemAddProduct,
        _itemRecordSale,
        _itemApproveTemplate,
      ].where(_isDone).length;

  bool get _shouldHideChecklist => _completedCount >= 3;

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _shouldHideChecklist) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'First steps in Spaza One',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$_completedCount / 4',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Hide',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _dismiss,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              // The R15 messaging credit is already surfaced
              // permanently via WalletBalancePill in PageHeader chrome
              // (lib/shared/widgets/page_header.dart:97), so we don't
              // need to repeat it in this subtitle.
              'Start with a customer so transactions, sales, and messages have a real person to work with.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            _buildItem(
              key: _itemAddCustomer,
              label: 'Add your first customer',
              onTap: widget.onAddCustomer,
            ),
            _buildItem(
              key: _itemAddProduct,
              label: 'Add a product when you need stock detail',
              onTap: widget.onAddProduct,
            ),
            _buildItem(
              key: _itemRecordSale,
              label: 'Record your first sale',
              onTap: widget.onRecordSale,
            ),
            _buildItem(
              key: _itemApproveTemplate,
              label: 'Approve a WhatsApp template',
              onTap: widget.onApproveTemplate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem({
    required String key,
    required String label,
    required VoidCallback onTap,
  }) {
    final done = _isDone(key);
    // PAS-UX-09: when a data signal flipped the item done, lock the
    // checkbox so the merchant can't accidentally untick reality.
    // Manual ticks remain editable for items still pending data.
    final dataDerived = done && _state[key] != true;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Checkbox(
              value: done,
              onChanged: dataDerived ? null : (v) => _toggle(key, v ?? false),
            ),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  decoration: done ? TextDecoration.lineThrough : null,
                  color: done ? Colors.grey : Colors.black87,
                ),
              ),
            ),
            if (!done)
              const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}
