import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/pages/promote/utils/template_status.dart';

/// Snapshot of everything the merchant setup card needs to render.
///
/// This is the single source of truth consumed by
/// [MerchantSetupCard]. All of the branching that used to live in six
/// nested `StreamBuilder`s inside the card widget now lives in
/// [watchMerchantSetup], which folds the six Firestore streams into
/// one stream of [MerchantSetupState] values.
///
/// Two states are worth calling out:
///
/// - [MerchantSetupState.loading] — used as the `initialData` of the
///   card's `StreamBuilder`, and also republished by the watcher until
///   every underlying stream has produced at least one value. The card
///   renders a skeleton in this state so we never flash the misleading
///   `0 of 6 done` header at merchants who already have data.
/// - `isComplete` — used by the card to swap to the store-link panel,
///   and by [CustomerTab] to unhide the customer growth nudge.
class MerchantSetupState {
  const MerchantSetupState({
    required this.hasCustomers,
    required this.hasProducts,
    required this.hasListedProduct,
    required this.hasOrderingLink,
    required this.hasApprovedTemplate,
    required this.hasBank,
    required this.shopName,
    required this.orderingUrl,
    required this.orderingCode,
    required this.fallbackText,
    required this.loading,
  });

  const MerchantSetupState.loading()
      : hasCustomers = false,
        hasProducts = false,
        hasListedProduct = false,
        hasOrderingLink = false,
        hasApprovedTemplate = false,
        hasBank = false,
        shopName = '',
        orderingUrl = '',
        orderingCode = '',
        fallbackText = '',
        loading = true;

  final bool hasCustomers;
  final bool hasProducts;
  final bool hasListedProduct;
  final bool hasOrderingLink;
  final bool hasApprovedTemplate;
  final bool hasBank;
  final String shopName;
  final String orderingUrl;
  final String orderingCode;
  final String fallbackText;
  final bool loading;

  /// Total number of steps the card shows. Kept as a getter so tests
  /// and the card share one definition and can't drift.
  int get totalSteps => 6;

  int get completedSteps {
    var n = 0;
    if (hasCustomers) n++;
    if (hasProducts) n++;
    if (hasListedProduct) n++;
    if (hasOrderingLink) n++;
    if (hasBank) n++;
    if (hasApprovedTemplate) n++;
    return n;
  }

  bool get isComplete => completedSteps == totalSteps;
}

/// Emits a fresh [MerchantSetupState] whenever any of the six underlying
/// Firestore signals changes.
///
/// A single stream + loading gate replaces the six-deep `StreamBuilder`
/// cascade that used to live inside the card widget. Real state is
/// only published once every underlying stream has produced at least
/// one snapshot; before that, `.loading()` is emitted so the card can
/// render a skeleton without special-casing "no data yet".
///
/// Uses a single-subscription controller so the six Firestore
/// listeners are torn down automatically when the card is disposed.
Stream<MerchantSetupState> watchMerchantSetup(String userId) {
  if (userId.isEmpty) {
    return Stream<MerchantSetupState>.value(
      const MerchantSetupState.loading(),
    );
  }

  final firestore = FirebaseFirestore.instance;
  final userDoc = firestore.collection('users').doc(userId);

  final userStream = userDoc.snapshots();
  final customerStream = userDoc.collection('customers').limit(1).snapshots();
  final productStream = userDoc.collection('products').limit(1).snapshots();
  final listedStream = userDoc
      .collection('products')
      .where('whatsappListed', isEqualTo: true)
      .limit(1)
      .snapshots();
  final bankStream = userDoc.collection('bankingDetails').limit(1).snapshots();
  // NOTE: We could shard this into two `.limit(1)` server-side
  // listeners (`approvalStatus == 'approved'` and the legacy
  // `approved == true`) and merge them, but for the tiny population
  // that has >5 templates a client-side scan of 5 is cheaper than two
  // active listeners. `templateStatusOf` honours both fields so
  // legacy docs without `approvalStatus` still count as approved
  // here.
  final templateStream = firestore
      .collection('messagingTemplates')
      .where('userId', isEqualTo: userId)
      .limit(5)
      .snapshots();

  late final StreamController<MerchantSetupState> controller;

  DocumentSnapshot<Map<String, dynamic>>? latestUser;
  QuerySnapshot<Map<String, dynamic>>? latestCustomers;
  QuerySnapshot<Map<String, dynamic>>? latestProducts;
  QuerySnapshot<Map<String, dynamic>>? latestListed;
  QuerySnapshot<Map<String, dynamic>>? latestBank;
  QuerySnapshot<Map<String, dynamic>>? latestTemplates;

  bool hasSeenAllOnce() =>
      latestUser != null &&
      latestCustomers != null &&
      latestProducts != null &&
      latestListed != null &&
      latestBank != null &&
      latestTemplates != null;

  void emit() {
    if (controller.isClosed) return;
    if (!hasSeenAllOnce()) {
      controller.add(const MerchantSetupState.loading());
      return;
    }

    final userData = latestUser?.data();
    final ordering = userData?['whatsappOrdering'];
    final orderingData = ordering is Map ? ordering : const {};
    final orderingCode = _mapString(orderingData, 'code');
    final storedOrderingUrl = _mapString(orderingData, 'orderingUrl');
    final pasellaWhatsappNumber =
        _mapString(orderingData, 'pasellaWhatsappNumber');
    final orderingUrl = storedOrderingUrl.isNotEmpty
        ? storedOrderingUrl
        : _buildOrderingUrl(
            code: orderingCode,
            pasellaWhatsappNumber: pasellaWhatsappNumber,
          );
    final fallbackText = _mapString(orderingData, 'fallbackText');
    final hasOrderingLink =
        orderingData['status'] == 'active' && orderingCode.isNotEmpty;
    final shopName = _firstNonEmpty([
      userData?['shopName'],
      userData?['name'],
      'your shop',
    ]);
    final hasApprovedTemplate = latestTemplates!.docs.any(
      (doc) => templateStatusOf(doc.data()) == TemplateStatus.approved,
    );

    controller.add(
      MerchantSetupState(
        hasCustomers: latestCustomers!.docs.isNotEmpty,
        hasProducts: latestProducts!.docs.isNotEmpty,
        hasListedProduct: latestListed!.docs.isNotEmpty,
        hasOrderingLink: hasOrderingLink,
        hasApprovedTemplate: hasApprovedTemplate,
        hasBank: latestBank!.docs.isNotEmpty,
        shopName: shopName,
        orderingUrl: orderingUrl,
        orderingCode: orderingCode,
        fallbackText: fallbackText,
        loading: false,
      ),
    );
  }

  final subs = <StreamSubscription<Object?>>[];

  void subscribeAll() {
    subs
      ..add(userStream.listen((snap) {
        latestUser = snap;
        emit();
      }, onError: controller.addError))
      ..add(customerStream.listen((snap) {
        latestCustomers = snap;
        emit();
      }, onError: controller.addError))
      ..add(productStream.listen((snap) {
        latestProducts = snap;
        emit();
      }, onError: controller.addError))
      ..add(listedStream.listen((snap) {
        latestListed = snap;
        emit();
      }, onError: controller.addError))
      ..add(bankStream.listen((snap) {
        latestBank = snap;
        emit();
      }, onError: controller.addError))
      ..add(templateStream.listen((snap) {
        latestTemplates = snap;
        emit();
      }, onError: controller.addError));
  }

  Future<void> cancelAll() async {
    for (final sub in subs) {
      await sub.cancel();
    }
    subs.clear();
  }

  controller = StreamController<MerchantSetupState>(
    onListen: subscribeAll,
    onPause: () {
      for (final sub in subs) {
        sub.pause();
      }
    },
    onResume: () {
      for (final sub in subs) {
        sub.resume();
      }
    },
    onCancel: cancelAll,
  );

  return controller.stream;
}

String _mapString(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  return value is String ? value.trim() : '';
}

String _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _buildOrderingUrl({
  required String code,
  required String pasellaWhatsappNumber,
}) {
  final digitsOnly = pasellaWhatsappNumber.replaceAll(RegExp(r'\D'), '');
  if (code.isEmpty || digitsOnly.isEmpty) return '';
  return 'https://wa.me/$digitsOnly?text=${Uri.encodeComponent('shop $code')}';
}
