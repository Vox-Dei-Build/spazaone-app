import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

class PromotionsViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
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

  bool _loadingTemplates = false;
  bool get loadingTemplates => _loadingTemplates;
  String shopName = '';

  Map<String, dynamic> promoBreakdown = {};

  /// call this once on create
  Future<void> loadInitialData() async {
    await Future.wait([
      fetchTemplates(),
      fetchMessageShopName(),
      initializePricing(),
      fetchCustomers(),
      fetchPromotionsReports(), // if needed
    ]);
  }

  /// if templates‐only tab needs less, you can also add:
  Future<void> loadTemplatesData() async {
    await Future.wait([
      fetchTemplates(),
      fetchMessageShopName(),
      initializePricing(),
    ]);
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

  Future<void> fetchMessageShopName() async {
    try {
      shopName = await fetchShopName();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to fetch shop name: $e');
    }
  }

  Future<bool> deleteTemplate(
      String docID, Map<String, dynamic> template) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Delete from Twilio via Cloud Function
      final callable =
          FirebaseFunctions.instance.httpsCallable('deleteTwilioTemplate');
      final twilioTemplateId =
          template['channels']?['whatsapp']?['twilioTemplateId'];

      if (twilioTemplateId != null) {
        await callable.call({'twilioTemplateId': twilioTemplateId});
      }

      // Delete from Firestore
      await FirebaseFirestore.instance
          .collection('messagingTemplates')
          .doc(docID)
          .delete();

      await loadTemplatesData();

      return true;
    } catch (e) {
      debugPrint('Delete error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchTemplates() async {
    _loadingTemplates = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('messagingTemplates')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      _templates = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // 🔥 Include Firestore document ID
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Failed to fetch templates: $e');
    } finally {
      _loadingTemplates = false;
      notifyListeners();
    }
  }

  Future<void> fetchCustomers() async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('customers')
          .get();

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

  void clearCustomerSelection() {
    selectedCustomerIds.clear();
    calculatePrice();
    notifyListeners();
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
      final customer =
          customers.firstWhere((c) => c['id'] == customerId, orElse: () => {});
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
    // linked-product chip on saved promotions. The snapshot is what
    // keeps the saved promo from silently breaking if the merchant
    // later edits or deletes the product. Backend doesn't need to
    // know about this field — it's UI metadata only.
    Map<String, dynamic>? linkedProduct,
  }) async {
    _sendingPromotion = true;
    notifyListeners();
    try {
      final docRef = await _firestore.collection('promotions').add({
        'merchantId': userId,
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
      _sendingPromotion = false;
      notifyListeners();
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
      final callable =
          FirebaseFunctions.instance.httpsCallable('runMerchantPromotion');
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
  Future<void> fetchPromotionsReports() async {
    loadingPromotions = true;
    notifyListeners();
    final snap = await _firestore
        .collection('promotions')
        .where('merchantId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .get();
    promotionsReports = snap.docs.map((d) {
      final m = d.data();
      m['id'] = d.id;
      return m;
    }).toList();
    loadingPromotions = false;
    notifyListeners();
  }

  Future<bool> deletePromotion(String promoId) async {
    try {
      await _firestore.collection('promotions').doc(promoId).delete();
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
