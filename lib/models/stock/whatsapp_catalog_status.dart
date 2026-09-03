enum WhatsAppCatalogRollout { enabled, notEnabled }

enum WhatsAppCatalogProductStatus {
  notListed,
  needsAttention,
  syncing,
  live,
  stale,
  reviewRequired,
  removalSyncing,
  supportReview;

  static WhatsAppCatalogProductStatus parse(Object? value) {
    return switch (value?.toString()) {
      'not_listed' => notListed,
      'needs_attention' => needsAttention,
      'syncing' => syncing,
      'live' => live,
      'stale' => stale,
      'review_required' => reviewRequired,
      'removal_syncing' => removalSyncing,
      'support_review' => supportReview,
      _ => supportReview,
    };
  }

  String get wireValue => switch (this) {
        notListed => 'not_listed',
        needsAttention => 'needs_attention',
        syncing => 'syncing',
        live => 'live',
        stale => 'stale',
        reviewRequired => 'review_required',
        removalSyncing => 'removal_syncing',
        supportReview => 'support_review',
      };

  String get label => switch (this) {
        notListed => 'Not listed',
        needsAttention => 'Needs attention',
        syncing => 'Syncing',
        live => 'Live on WhatsApp',
        stale => 'Updating',
        reviewRequired => 'Review required',
        removalSyncing => 'Removing from WhatsApp',
        supportReview => 'Support review',
      };
}

enum WhatsAppCatalogProductAction {
  none,
  editProduct,
  completeShopLink,
  refresh,
  contactSupport;

  static WhatsAppCatalogProductAction parse(Object? value) {
    return switch (value?.toString()) {
      'edit_product' => editProduct,
      'complete_shop_link' => completeShopLink,
      'refresh' => refresh,
      'contact_support' => contactSupport,
      _ => none,
    };
  }

  String get wireValue => switch (this) {
        none => 'none',
        editProduct => 'edit_product',
        completeShopLink => 'complete_shop_link',
        refresh => 'refresh',
        contactSupport => 'contact_support',
      };
}

class WhatsAppCatalogProductState {
  const WhatsAppCatalogProductState({
    required this.productId,
    required this.status,
    required this.reasonCodes,
    required this.action,
    required this.updatedAtMs,
    this.supportReference,
  });

  final String productId;
  final WhatsAppCatalogProductStatus status;
  final List<String> reasonCodes;
  final WhatsAppCatalogProductAction action;
  final int updatedAtMs;
  final String? supportReference;

  factory WhatsAppCatalogProductState.fromMap(Map<String, dynamic> map) {
    final rawStatus = map['status']?.toString();
    final status = WhatsAppCatalogProductStatus.parse(rawStatus);
    final knownStatus = WhatsAppCatalogProductStatus.values
        .any((value) => value.wireValue == rawStatus);
    return WhatsAppCatalogProductState(
      productId: map['productId']?.toString() ?? '',
      status: status,
      reasonCodes: knownStatus
          ? List<String>.unmodifiable(
              (map['reasonCodes'] as List? ?? const [])
                  .map((reason) => reason.toString()),
            )
          : const ['unknown_status'],
      action: knownStatus
          ? WhatsAppCatalogProductAction.parse(map['action'])
          : WhatsAppCatalogProductAction.contactSupport,
      updatedAtMs: _asInt(map['updatedAtMs']),
      supportReference: map['supportReference']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'status': status.wireValue,
        'reasonCodes': reasonCodes,
        'action': action.wireValue,
        'updatedAtMs': updatedAtMs,
        if (supportReference != null) 'supportReference': supportReference,
      };
}

class WhatsAppCatalogSummary {
  const WhatsAppCatalogSummary({
    required this.totalProducts,
    required this.eligible,
    required this.live,
    required this.syncing,
    required this.needsAttention,
    required this.removalSyncing,
    required this.supportReview,
    required this.canBrowseFive,
    required this.canBrowseTen,
  });

  final int totalProducts;
  final int eligible;
  final int live;
  final int syncing;
  final int needsAttention;
  final int removalSyncing;
  final int supportReview;
  final bool canBrowseFive;
  final bool canBrowseTen;

  factory WhatsAppCatalogSummary.fromMap(Map<String, dynamic> map) =>
      WhatsAppCatalogSummary(
        totalProducts: _asInt(map['totalProducts']),
        eligible: _asInt(map['eligible']),
        live: _asInt(map['live']),
        syncing: _asInt(map['syncing']),
        needsAttention: _asInt(map['needsAttention']),
        removalSyncing: _asInt(map['removalSyncing']),
        supportReview: _asInt(map['supportReview']),
        canBrowseFive: map['canBrowseFive'] == true,
        canBrowseTen: map['canBrowseTen'] == true,
      );

  Map<String, dynamic> toMap() => {
        'totalProducts': totalProducts,
        'eligible': eligible,
        'live': live,
        'syncing': syncing,
        'needsAttention': needsAttention,
        'removalSyncing': removalSyncing,
        'supportReview': supportReview,
        'canBrowseFive': canBrowseFive,
        'canBrowseTen': canBrowseTen,
      };
}

class WhatsAppCatalogSnapshot {
  WhatsAppCatalogSnapshot({
    required this.checkedAtMs,
    required this.freshUntilMs,
    required this.rollout,
    required this.summary,
    required this.products,
    required this.catalogVersion,
    this.fromCache = false,
  }) : productsById = {
          for (final product in products)
            if (product.productId.isNotEmpty) product.productId: product,
        };

  final int checkedAtMs;
  final int freshUntilMs;
  final WhatsAppCatalogRollout rollout;
  final WhatsAppCatalogSummary summary;
  final List<WhatsAppCatalogProductState> products;
  final String catalogVersion;
  final bool fromCache;
  final Map<String, WhatsAppCatalogProductState> productsById;

  bool isStaleAt(DateTime now) => now.millisecondsSinceEpoch > freshUntilMs;
  bool get hasPendingWork => products.any(
        (product) =>
            product.status == WhatsAppCatalogProductStatus.syncing ||
            product.status == WhatsAppCatalogProductStatus.removalSyncing,
      );

  factory WhatsAppCatalogSnapshot.fromMap(
    Map<String, dynamic> map, {
    bool fromCache = false,
  }) {
    if (_asInt(map['schemaVersion']) != 2) {
      throw const FormatException('Unsupported catalogue status response.');
    }
    final summary = Map<String, dynamic>.from(map['summary'] as Map? ?? {});
    return WhatsAppCatalogSnapshot(
      checkedAtMs: _asInt(map['checkedAtMs']),
      freshUntilMs: _asInt(map['freshUntilMs']),
      rollout: map['rollout'] == 'enabled'
          ? WhatsAppCatalogRollout.enabled
          : WhatsAppCatalogRollout.notEnabled,
      summary: WhatsAppCatalogSummary.fromMap(summary),
      products: List<WhatsAppCatalogProductState>.unmodifiable(
        (map['products'] as List? ?? const []).map(
          (product) => WhatsAppCatalogProductState.fromMap(
            Map<String, dynamic>.from(product as Map),
          ),
        ),
      ),
      catalogVersion: map['catalogVersion']?.toString() ?? '',
      fromCache: fromCache,
    );
  }

  Map<String, dynamic> toMap() => {
        'schemaVersion': 2,
        'checkedAtMs': checkedAtMs,
        'freshUntilMs': freshUntilMs,
        'rollout': rollout == WhatsAppCatalogRollout.enabled
            ? 'enabled'
            : 'not_enabled',
        'summary': summary.toMap(),
        'products': products.map((product) => product.toMap()).toList(),
        'catalogVersion': catalogVersion,
        'retryPermitted': false,
      };
}

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
