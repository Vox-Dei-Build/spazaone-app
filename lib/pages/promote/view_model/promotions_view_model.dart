import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

const productPromotionTemplateKind = 'product_promotion_v1';

class PromotionsViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final StreamSubscription<User?> _authSubscription;
  String _activeMerchantId = '';

  PromotionsViewModel() {
    _activeMerchantId = userId;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      final nextMerchantId = user?.uid.trim() ?? '';
      if (nextMerchantId == _activeMerchantId) return;
      _activeMerchantId = nextMerchantId;
      _clearMerchantScopedState();
      notifyListeners();
    });
  }

  String get userId => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  double? whatsappPrice;
  double? smsPricePerSegment;
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  String? selectedTemplateId;
  List<String> selectedCustomerIds = [];
  double totalPrice = 0.0;
  List<Map<String, dynamic>> customers = [];
  bool loadingPromotions = false;
  List<Map<String, dynamic>> promotionsReports = [];

  /// Count of customers that were filtered out by [fetchCustomers] because
  /// they have no usable phone number. Exposed so the customer-selection
  /// step can surface a small "X customers hidden (no number)" hint
  /// rather than silently dropping them.
  int customersWithoutNumberCount = 0;

  /// PAS-WA-03: cached WhatsApp capability keyed by customer id.
  ///
  /// - `true`  → we have a `successfulWhatsAppNumbers` record marking
  ///   this number as WA-reachable.
  /// - `false` → we have a record explicitly marking it not reachable
  ///   (e.g. a previous send proved it).
  /// - missing → we've never checked. Treated as "unknown" by the
  ///   customer selection step so the merchant isn't denied the
  ///   ability to attempt a send (the runtime path already does a
  ///   live check before charging).
  ///
  /// Populated by [loadWhatsAppCapability], called by the wizard
  /// just-in-time before showing step 2 so we don't pay the
  /// per-customer Firestore lookup cost during the initial load.
  Map<String, bool> whatsAppCapableById = {};
  bool _loadingWhatsAppCapability = false;
  bool get loadingWhatsAppCapability => _loadingWhatsAppCapability;

  /// Returns true if [customer] has a non-empty `number` field. Used to
  /// keep numberless customers out of the promotion recipient list
  /// (they would be skipped at send time anyway — there's no value in
  /// letting the merchant pick them as recipients).
  static bool customerHasNumber(Map<String, dynamic> customer) {
    final raw = customer['number'];
    if (raw == null) return false;
    return raw.toString().trim().isNotEmpty;
  }

  // -- TEMPLATES
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> get templates => _templates;

  /// The single Pasella-owned template used by the product-first promotion
  /// flow. User-authored templates remain in Firestore for backwards
  /// compatibility but are not part of the everyday merchant journey.
  Map<String, dynamic>? get productPromotionTemplate {
    for (final template in _templates) {
      if (template['systemManaged'] == true &&
          template['templateKind'] == productPromotionTemplateKind) {
        return template;
      }
    }
    return null;
  }

  bool _loadingTemplates = false;
  bool get loadingTemplates => _loadingTemplates;
  String shopName = '';
  String merchantMobileNumber = '';

  Map<String, dynamic> promoBreakdown = {};

  String? _prepareMerchantScope() {
    final merchantId = userId;
    if (merchantId != _activeMerchantId) {
      _activeMerchantId = merchantId;
      _clearMerchantScopedState();
    }
    return merchantId.isEmpty ? null : merchantId;
  }

  bool _isStillCurrentMerchant(String merchantId) {
    return userId == merchantId && _activeMerchantId == merchantId;
  }

  void _clearMerchantScopedState() {
    selectedTemplateId = null;
    selectedCustomerIds = [];
    totalPrice = 0.0;
    customers = [];
    customersWithoutNumberCount = 0;
    whatsAppCapableById = {};
    promoBreakdown = {};
    _templates = [];
    promotionsReports = [];
    shopName = '';
    merchantMobileNumber = '';
    _loadingTemplates = false;
    loadingPromotions = false;
    _loadingWhatsAppCapability = false;
  }

  /// call this once on create
  Future<void> loadInitialData() async {
    final merchantId = _prepareMerchantScope();
    if (merchantId == null) {
      notifyListeners();
      return;
    }

    await Future.wait([
      fetchTemplates(merchantId: merchantId),
      fetchMessageShopName(merchantId: merchantId),
      initializePricing(),
      fetchCustomers(merchantId: merchantId),
      fetchPromotionsReports(merchantId: merchantId), // if needed
    ]);
  }

  /// if templates‐only tab needs less, you can also add:
  Future<void> loadTemplatesData() async {
    final merchantId = _prepareMerchantScope();
    if (merchantId == null) {
      notifyListeners();
      return;
    }

    await Future.wait([
      fetchTemplates(merchantId: merchantId),
      fetchMessageShopName(merchantId: merchantId),
      initializePricing(),
    ]);
  }

  /// Ensures Pasella's reusable product-promotion template exists and has
  /// been submitted for WhatsApp approval. The callable is idempotent, so it
  /// is safe to invoke whenever Marketing or a product-level Promote action
  /// opens. Returns the refreshed merchant binding document when available.
  Future<Map<String, dynamic>?> ensureProductPromotionTemplate({
    bool retry = false,
  }) async {
    final merchantId = _prepareMerchantScope();
    if (merchantId == null) return null;
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'ensureProductPromotionTemplate',
      );
      await callable.call({'retry': retry});
      await fetchTemplates(merchantId: merchantId);
      return productPromotionTemplate;
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        'ensureProductPromotionTemplate callable failure: ${e.code} ${e.message}',
      );
      await fetchTemplates(merchantId: merchantId);
      return productPromotionTemplate;
    } catch (e) {
      debugPrint('ensureProductPromotionTemplate failed: $e');
      return productPromotionTemplate;
    }
  }

  // initialize pricing, e.g.:
  Future<void> initializePricing() async {
    final pricingService = await DynamicPricingService.initialize();
    whatsappPrice = pricingService.whatsappPromotionPrice;
    smsPricePerSegment = pricingService.smsReminderTemplatePrice;
    notifyListeners();
  }

  void selectTemplate(String templateId) {
    selectedTemplateId = templateId;
    calculatePrice();
    notifyListeners();
  }

  void toggleCustomerSelection(String customerId) {
    selectedCustomerIds.contains(customerId)
        ? selectedCustomerIds.remove(customerId)
        : selectedCustomerIds.add(customerId);
    calculatePrice();
    notifyListeners();
  }

  void calculatePrice() {
    int count = selectedCustomerIds.length;
    totalPrice = count * (whatsappPrice ?? 0);
  }

  Future<void> fetchMessageShopName({String? merchantId}) async {
    final scopedMerchantId = merchantId ?? _prepareMerchantScope();
    if (scopedMerchantId == null) {
      shopName = '';
      merchantMobileNumber = '';
      notifyListeners();
      return;
    }

    try {
      final snapshot =
          await _firestore.collection('users').doc(scopedMerchantId).get();
      final data = snapshot.data();
      if (!_isStillCurrentMerchant(scopedMerchantId)) return;
      shopName = data?['shopName']?.toString().trim() ?? '';
      merchantMobileNumber =
          data?['mobileNumber']?.toString().trim().isNotEmpty == true
              ? data!['mobileNumber'].toString().trim()
              : FirebaseAuth.instance.currentUser?.phoneNumber?.trim() ?? '';
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to fetch shop name: $e');
    }
  }

  Future<bool> deleteTemplate(
    String docID,
    Map<String, dynamic> template,
  ) async {
    if (template['systemManaged'] == true) return false;
    final merchantId = _prepareMerchantScope();
    if (merchantId == null) return false;

    _isLoading = true;
    notifyListeners();

    try {
      final templateRef = FirebaseFirestore.instance
          .collection('messagingTemplates')
          .doc(docID);
      final templateSnap = await templateRef.get();
      final templateData = templateSnap.data();
      if (!templateSnap.exists ||
          templateData == null ||
          templateData['userId'] != merchantId) {
        throw StateError('Template does not belong to the current merchant.');
      }
      if (templateData['systemManaged'] == true) {
        throw StateError('Pasella-managed templates cannot be deleted.');
      }

      // Delete from Twilio via Cloud Function
      final callable = FirebaseFunctions.instance.httpsCallable(
        'deleteTwilioTemplate',
      );
      final twilioTemplateId =
          templateData['channels']?['whatsapp']?['twilioTemplateId'];

      if (twilioTemplateId != null) {
        await callable.call({
          'templateId': docID,
          'twilioTemplateId': twilioTemplateId,
        });
      }

      // Delete from Firestore
      await templateRef.delete();

      await loadTemplatesData();

      return true;
    } catch (e) {
      debugPrint('Delete error: $e');
      return false;
    } finally {
      if (_isStillCurrentMerchant(merchantId)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> fetchTemplates({String? merchantId}) async {
    final scopedMerchantId = merchantId ?? _prepareMerchantScope();
    if (scopedMerchantId == null) {
      _templates = [];
      _loadingTemplates = false;
      notifyListeners();
      return;
    }

    _loadingTemplates = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('messagingTemplates')
          .where('userId', isEqualTo: scopedMerchantId)
          .orderBy('createdAt', descending: true)
          .get();

      if (!_isStillCurrentMerchant(scopedMerchantId)) return;
      _templates = snapshot.docs
          .map((doc) {
            final data = doc.data();
            data['id'] = doc.id; // 🔥 Include Firestore document ID
            return data;
          })
          .where((data) => data['userId'] == scopedMerchantId)
          .toList();
    } catch (e) {
      debugPrint('Failed to fetch templates: $e');
    } finally {
      if (_isStillCurrentMerchant(scopedMerchantId)) {
        _loadingTemplates = false;
        notifyListeners();
      }
    }
  }

  Future<void> fetchCustomers({String? merchantId}) async {
    final scopedMerchantId = merchantId ?? _prepareMerchantScope();
    if (scopedMerchantId == null) {
      customers = [];
      customersWithoutNumberCount = 0;
      notifyListeners();
      return;
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(scopedMerchantId)
          .collection('customers')
          .get();

      if (!_isStillCurrentMerchant(scopedMerchantId)) return;
      final all = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Promotions can only be delivered to customers with a phone
      // number. Numberless customers used to appear in the recipient
      // list as selectable rows, get included in `selectAllCustomers`,
      // and then get silently dropped by the send path — leaving the
      // merchant with a mismatched "selected vs delivered" count and
      // no explanation. Filter at the source so the UI, "select all",
      // and pricing breakdown all agree on the same recipient set.
      customers = all.where(customerHasNumber).toList();
      customersWithoutNumberCount = all.length - customers.length;

      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching customers: $e');
    }
  }

  void selectAllCustomers() {
    selectedCustomerIds = customers.map((c) => c['id'] as String).toList();
    calculatePrice();
    notifyListeners();
  }

  /// PAS-WA-03: select every customer in [eligible] (typically the
  /// channel-filtered subset shown in step 2). Used by "All Customers"
  /// so the selection matches what the merchant sees rather than the
  /// full numbered-customer list.
  void selectAllFromEligible(List<Map<String, dynamic>> eligible) {
    selectedCustomerIds = eligible.map((c) => c['id'] as String).toList();
    calculatePrice();
    notifyListeners();
  }

  void selectCustomerIds(Iterable<String> ids) {
    selectedCustomerIds = ids.toSet().toList();
    calculatePrice();
    notifyListeners();
  }

  /// PAS-WA-03: batch-load WhatsApp capability for the loaded
  /// customers. We hit `successfulWhatsAppNumbers` once per
  /// (normalized) number — the collection isn't keyed by id so a
  /// single `whereIn` is the cheapest way to populate the cache
  /// without N round-trips. Firestore `whereIn` caps at 30 values per
  /// query, so we chunk.
  ///
  /// Customers with no record are simply absent from
  /// [whatsAppCapableById] — i.e. "unknown". The wizard treats
  /// unknown as "include in WhatsApp-only filter and surface in the
  /// banner" (see audit decision: "Include them, mark in banner")
  /// rather than excluding pre-emptively, because the send path
  /// already does a live check and only charges on success.
  Future<void> loadWhatsAppCapability() async {
    if (customers.isEmpty) return;
    final merchantId = _prepareMerchantScope();
    if (merchantId == null) return;

    _loadingWhatsAppCapability = true;
    notifyListeners();
    try {
      final numbers = <String>{};
      final numberToCustomerIds = <String, List<String>>{};
      for (final c in customers) {
        final raw = c['number'];
        if (raw == null) continue;
        final normalized = normalizePhoneNumber(raw.toString());
        if (normalized.isEmpty) continue;
        numbers.add(normalized);
        numberToCustomerIds
            .putIfAbsent(normalized, () => <String>[])
            .add(c['id'] as String);
      }

      final result = <String, bool>{};
      final list = numbers.toList();
      // Firestore `whereIn` allows up to 30 elements per query.
      const chunkSize = 30;
      for (var i = 0; i < list.length; i += chunkSize) {
        final chunk = list.sublist(
          i,
          i + chunkSize > list.length ? list.length : i + chunkSize,
        );
        final snap = await _firestore
            .collection('successfulWhatsAppNumbers')
            .where('phoneNumber', whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final phone = data['phoneNumber'] as String?;
          final has = data['hasWhatsApp'] as bool? ?? false;
          if (phone == null) continue;
          final ids = numberToCustomerIds[phone];
          if (ids == null) continue;
          for (final id in ids) {
            result[id] = has;
          }
        }
      }
      if (!_isStillCurrentMerchant(merchantId)) return;
      whatsAppCapableById = result;
    } catch (e) {
      debugPrint('Failed to load WhatsApp capability: $e');
    } finally {
      if (_isStillCurrentMerchant(merchantId)) {
        _loadingWhatsAppCapability = false;
        notifyListeners();
      }
    }
  }

  /// PAS-WA-03: filter the loaded customers down to the subset that
  /// is reachable given the selected channels. Logic:
  ///
  /// - **SMS only**: every numbered customer is eligible (any number
  ///   we can format can receive SMS).
  /// - **WhatsApp only**: known-WA customers + customers with no cached
  ///   capability (unknown). Known not-WA customers are excluded — the
  ///   merchant would be paying for sends Twilio is going to drop.
  /// - **Both**: every numbered customer is eligible (WA where possible,
  ///   SMS otherwise).
  ///
  /// Returns a record of: the filtered list, the count of
  /// known-not-WA customers hidden by the filter (so the banner can
  /// explain), and the count of unknown-capability customers included
  /// (so the banner can warn that some sends may fall back / not
  /// deliver).
  ({
    List<Map<String, dynamic>> eligible,
    int hiddenNotWhatsApp,
    int unknownIncluded,
  }) filterCustomersForChannels({
    required bool sendWhatsApp,
    required bool sendSMS,
  }) {
    if (sendSMS || (!sendWhatsApp && !sendSMS)) {
      // SMS-only or both → every numbered customer. (The "neither"
      // case shouldn't happen because step 1 validation requires
      // ≥1 channel, but degrade gracefully.)
      return (eligible: customers, hiddenNotWhatsApp: 0, unknownIncluded: 0);
    }
    // WhatsApp only.
    final eligible = <Map<String, dynamic>>[];
    var hiddenNotWa = 0;
    var unknown = 0;
    for (final c in customers) {
      final id = c['id'] as String?;
      if (id == null) continue;
      final cap = whatsAppCapableById[id];
      if (cap == true) {
        eligible.add(c);
      } else if (cap == false) {
        hiddenNotWa++;
      } else {
        eligible.add(c);
        unknown++;
      }
    }
    return (
      eligible: eligible,
      hiddenNotWhatsApp: hiddenNotWa,
      unknownIncluded: unknown,
    );
  }

  void clearCustomerSelection() {
    selectedCustomerIds.clear();
    calculatePrice();
    notifyListeners();
  }

  /// Rule-based V1 recommendation: customers with ledger activity in the
  /// last 90 days. If the merchant has no recent activity data, all eligible
  /// customers are returned so the default never becomes an empty dead end.
  static List<Map<String, dynamic>> recommendedCustomers(
    List<Map<String, dynamic>> eligible, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final cutoff = reference.subtract(const Duration(days: 90));
    final recent = eligible.where((customer) {
      final last = customer['lastTransaction'];
      if (last is! Map) return false;
      final rawDate = last['date'];
      final date = rawDate is Timestamp ? rawDate.toDate() : null;
      return date != null && !date.isBefore(cutoff);
    }).toList();
    return recent.isEmpty ? List.of(eligible) : recent;
  }

  /// A maximum estimate for the automatic product flow. Known WhatsApp
  /// recipients use the approved card, known non-WhatsApp recipients use SMS,
  /// and unknown numbers are priced at the more expensive of the two because
  /// the backend checks WhatsApp first and falls back without user input.
  Map<String, dynamic> estimateProductPromotion({
    required String smsContent,
  }) {
    final whatsappUnit = whatsappPrice ?? 0.0;
    final smsUnit = smsPricePerSegment ?? 0.0;
    final smsSegments = calculateSmsSegments(smsContent);
    final smsRecipientCost = smsUnit * smsSegments;
    var whatsappCount = 0;
    var smsCount = 0;
    var unknownCount = 0;

    for (final id in selectedCustomerIds) {
      final capability = whatsAppCapableById[id];
      if (capability == true) {
        whatsappCount++;
      } else if (capability == false) {
        smsCount++;
      } else {
        unknownCount++;
      }
    }

    final unknownUnit =
        whatsappUnit > smsRecipientCost ? whatsappUnit : smsRecipientCost;
    final total = whatsappCount * whatsappUnit +
        smsCount * smsRecipientCost +
        unknownCount * unknownUnit;
    return {
      'total': total,
      'whatsappCount': whatsappCount,
      'whatsappUnit': whatsappUnit,
      'smsCount': smsCount,
      'smsUnit': smsUnit,
      'smsSegments': smsSegments,
      'unknownCount': unknownCount,
      'unknownUnit': unknownUnit,
    };
  }

  int calculateSmsSegments(String text) {
    return SMSPricingUtil.calculateSegments(text);
  }

  Future<Map<String, dynamic>> calculatePriceWithBreakdown(
    bool sendWhatsApp,
    bool sendSMS,
    String? smsContent,
  ) async {
    double total = 0.0;
    int whatsappCount = 0;
    int smsCount = 0;
    int smsSegments = 1;

    if (sendSMS && smsContent != null) {
      smsSegments = calculateSmsSegments(smsContent);
    }

    for (final customerId in selectedCustomerIds) {
      final customer = customers.firstWhere(
        (c) => c['id'] == customerId,
        orElse: () => {},
      );
      final phone = customer['number'];
      if (phone == null) continue;

      final normalizedPhone = normalizePhoneNumber(phone);
      final status = await fetchWhatsAppStatus(normalizedPhone);
      final hasWhatsApp = status?['hasWhatsApp'] ?? false;

      if (hasWhatsApp && sendWhatsApp) {
        total += whatsappPrice ?? 0;
        whatsappCount++;
      } else if (sendSMS) {
        final smsUnit = smsPricePerSegment ?? 0;
        total += smsUnit * smsSegments;
        smsCount++;
      }
    }

    return {
      'total': total,
      'whatsappCount': whatsappCount,
      'smsCount': smsCount,
      'whatsappUnit': whatsappPrice ?? 0,
      'smsUnit': smsPricePerSegment ?? 0,
      'smsSegments': smsSegments,
    };
  }

  Future<Map<String, dynamic>?> fetchWhatsAppStatus(String phoneNumber) async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('successfulWhatsAppNumbers')
        .where('phoneNumber', isEqualTo: phoneNumber)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      final data = querySnapshot.docs.first.data();
      return {
        'hasWhatsApp': data['hasWhatsApp'] ?? false, // Ensure boolean value
        'lastChecked': (data['lastChecked'] as Timestamp?)?.toDate(),
      };
    }

    return null; // No record found → we've never checked before
  }

  // -- PROMOTION STATUS / SENDING LOGIC
  bool _sendingPromotion = false;
  bool get sendingPromotion => _sendingPromotion;

  Future<String?> savePromotion({
    required String templateId,
    required List<String> customerIds,
    required Map<String, String> variables,
    required bool sendWhatsApp,
    required bool sendSMS,
    required bool testMode,
    // PAS-UX-rel #5: optional product link. We store both the id
    // (canonical pointer back to `users/{uid}/products/{id}`) and a
    // denormalized snapshot of the fields the UI needs to render the
    // linked-product chip on saved promotions. The backend reloads the
    // canonical product by this id before sending, while the snapshot keeps
    // historical promotion cards readable if the product is later edited.
    Map<String, dynamic>? linkedProduct,
  }) async {
    final merchantId = _prepareMerchantScope();
    if (merchantId == null) return null;

    _sendingPromotion = true;
    notifyListeners();
    try {
      final templateSnap = await _firestore
          .collection('messagingTemplates')
          .doc(templateId)
          .get();
      final templateData = templateSnap.data();
      if (!templateSnap.exists ||
          templateData == null ||
          templateData['userId'] != merchantId) {
        throw StateError('Template does not belong to the current merchant.');
      }

      final docRef = await _firestore.collection('promotions').add({
        'merchantId': merchantId,
        'templateId': templateId,
        'customerIds': customerIds,
        'variables': variables,
        'sendWhatsApp': sendWhatsApp,
        'sendSMS': sendSMS,
        'testMode': testMode,
        'status': 'saved',
        'createdAt': FieldValue.serverTimestamp(),
        if (linkedProduct != null) 'linkedProduct': linkedProduct,
      });
      await fetchPromotionsReports();
      return docRef.id; // ← return the new ID
    } catch (e) {
      debugPrint('Failed to save promotion: $e');
      return null;
    } finally {
      if (_isStillCurrentMerchant(merchantId)) {
        _sendingPromotion = false;
        notifyListeners();
      }
    }
  }

  Future<SendPromotionResult> sendSavedPromotion(String promoId) async {
    // PAS-WA-01: the callable used to be invoked with no error
    // handling at all — a FirebaseFunctionsException would bubble
    // unhandled while the awaiting UI just popped back, leaving the
    // merchant with no feedback. We now always return a structured
    // result so callers can show a snackbar/banner with either the
    // provider error preserved by the backend or the Pasella-side
    // fallback when the provider gave us nothing.
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'runMerchantPromotion',
      );
      final res = await callable.call({'promotionId': promoId});
      final data = (res.data as Map?) ?? const {};
      if (data['success'] == true) {
        // Refresh reports so we can read back the terminal status
        // (`complete` / `partial` / `failed`) and per-recipient
        // counts the function just wrote.
        await fetchPromotionsReports();
        final promo = promotionsReports.firstWhere(
          (p) => p['id'] == promoId,
          orElse: () => <String, dynamic>{},
        );
        final status = promo['status'] as String?;
        final failedCount = (promo['failedCount'] as num?)?.toInt() ?? 0;
        final succeededCount = (promo['succeededCount'] as num?)?.toInt() ?? 0;
        final lastError = promo['lastErrorMessage'] as String?;
        if (status == 'failed') {
          return SendPromotionResult.failed(
            message: lastError ??
                'No messages could be delivered. Provider gave no further detail — '
                    'treat as transient and retry, then contact support if it persists.',
            failedCount: failedCount,
            succeededCount: succeededCount,
          );
        }
        if (status == 'partial') {
          return SendPromotionResult.partial(
            message: lastError ??
                'Some messages could not be delivered. See the promotion details for the affected recipients.',
            failedCount: failedCount,
            succeededCount: succeededCount,
          );
        }
        return SendPromotionResult.ok(succeededCount: succeededCount);
      }
      return SendPromotionResult.failed(
        message:
            'The send did not complete successfully. Please retry or contact support if it keeps happening.',
        failedCount: 0,
        succeededCount: 0,
      );
    } on FirebaseFunctionsException catch (e) {
      // Preserve whatever the callable layer gave us, but always
      // provide a usable fallback so we never leave the merchant
      // staring at a silent failure.
      final detail = (e.message != null && e.message!.trim().isNotEmpty)
          ? e.message!
          : 'Send failed (code: ${e.code}). No further detail returned — '
              'retry, then contact support if it persists.';
      debugPrint('sendSavedPromotion callable failure: ${e.code} ${e.message}');
      return SendPromotionResult.failed(
        message: detail,
        failedCount: 0,
        succeededCount: 0,
      );
    } catch (e) {
      debugPrint('sendSavedPromotion unexpected error: $e');
      return SendPromotionResult.failed(
        message:
            'Send failed unexpectedly. Check your connection and retry, then contact support if it persists.',
        failedCount: 0,
        succeededCount: 0,
      );
    }
  }

  // -- REPORTS (Simplified)
  Future<void> fetchPromotionsReports({String? merchantId}) async {
    final scopedMerchantId = merchantId ?? _prepareMerchantScope();
    if (scopedMerchantId == null) {
      promotionsReports = [];
      loadingPromotions = false;
      notifyListeners();
      return;
    }

    loadingPromotions = true;
    notifyListeners();
    try {
      final snap = await _firestore
          .collection('promotions')
          .where('merchantId', isEqualTo: scopedMerchantId)
          .orderBy('createdAt', descending: true)
          .get();
      if (!_isStillCurrentMerchant(scopedMerchantId)) return;
      promotionsReports = snap.docs
          .map((d) {
            final m = d.data();
            m['id'] = d.id;
            return m;
          })
          .where((data) => data['merchantId'] == scopedMerchantId)
          .toList();
    } catch (e) {
      debugPrint('Failed to fetch promotions: $e');
    } finally {
      if (_isStillCurrentMerchant(scopedMerchantId)) {
        loadingPromotions = false;
        notifyListeners();
      }
    }
  }

  Future<bool> deletePromotion(String promoId) async {
    final merchantId = _prepareMerchantScope();
    if (merchantId == null) return false;

    try {
      final promoRef = _firestore.collection('promotions').doc(promoId);
      final promoSnap = await promoRef.get();
      final promoData = promoSnap.data();
      if (!promoSnap.exists ||
          promoData == null ||
          promoData['merchantId'] != merchantId) {
        throw StateError('Promotion does not belong to the current merchant.');
      }

      await promoRef.delete();
      await fetchPromotionsReports();
      return true;
    } catch (e) {
      debugPrint('Delete error: $e');
      return false;
    }
  }

  /// The currently‐selected template’s WhatsApp content
  String? get currentTemplateContent {
    final t = templates.firstWhere(
      (t) => t['id'] == selectedTemplateId,
      orElse: () => <String, dynamic>{},
    );
    return (t['channels']?['whatsapp']?['templateContent']) as String?;
  }

  /// The currently‐selected template’s WhatsApp media URL
  String? get currentMediaUrl {
    final t = templates.firstWhere(
      (t) => t['id'] == selectedTemplateId,
      orElse: () => <String, dynamic>{},
    );
    return (t['channels']?['whatsapp']?['mediaUrl']) as String?;
  }

  // Preload a saved promo into your RunPromotionPage state
  Future<void> loadPromotionIntoState(Map<String, dynamic> promo) async {
    final merchantId = _prepareMerchantScope();
    if (merchantId == null || promo['merchantId'] != merchantId) return;

    // 1) template
    selectedTemplateId = promo['templateId'] as String?;

    // 2) channel flags
    var sendWhatsApp = promo['sendWhatsApp'] as bool? ?? true;
    var sendSMS = promo['sendSMS'] as bool? ?? true;

    // 3) customers
    selectedCustomerIds = List<String>.from(promo['customerIds'] ?? []);

    // 5) extract SMS content from the selected template
    final template = templates.firstWhere(
      (t) => t['id'] == selectedTemplateId,
      orElse: () => <String, dynamic>{},
    );
    final smsContent =
        (template['channels']?['whatsapp']?['templateContent']) as String?;

    // 6) recalc breakdown & total
    final breakdown = await calculatePriceWithBreakdown(
      sendWhatsApp,
      sendSMS,
      smsContent,
    );

    promoBreakdown = breakdown;
    totalPrice = (breakdown['total'] as num).toDouble();

    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }
}

/// PAS-WA-01: structured outcome of a `sendSavedPromotion` call.
///
/// The previous `Future<void>` shape gave callers no way to react to
/// per-recipient failures or to a callable-layer crash, which is why
/// the audit found merchants getting no feedback at all on broken
/// sends. The three states map directly to the backend terminal
/// statuses (`complete` / `partial` / `failed`) plus an explicit
/// failure path for transport/callable errors. `message` is always
/// populated — even in the fallback case — so a UI can show a
/// snackbar/banner without having to invent its own copy.
enum SendPromotionOutcome { ok, partial, failed }

class SendPromotionResult {
  final SendPromotionOutcome outcome;
  final String? message;
  final int succeededCount;
  final int failedCount;

  const SendPromotionResult._({
    required this.outcome,
    required this.message,
    required this.succeededCount,
    required this.failedCount,
  });

  factory SendPromotionResult.ok({int succeededCount = 0}) =>
      SendPromotionResult._(
        outcome: SendPromotionOutcome.ok,
        message: null,
        succeededCount: succeededCount,
        failedCount: 0,
      );

  factory SendPromotionResult.partial({
    required String message,
    required int succeededCount,
    required int failedCount,
  }) =>
      SendPromotionResult._(
        outcome: SendPromotionOutcome.partial,
        message: message,
        succeededCount: succeededCount,
        failedCount: failedCount,
      );

  factory SendPromotionResult.failed({
    required String message,
    required int succeededCount,
    required int failedCount,
  }) =>
      SendPromotionResult._(
        outcome: SendPromotionOutcome.failed,
        message: message,
        succeededCount: succeededCount,
        failedCount: failedCount,
      );

  bool get isOk => outcome == SendPromotionOutcome.ok;
  bool get hasFailures => failedCount > 0 || outcome != SendPromotionOutcome.ok;
}
