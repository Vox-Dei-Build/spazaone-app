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

      customers = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

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

  Future<void> sendSavedPromotion(String promoId) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('runMerchantPromotion');
    final res = await callable.call({'promotionId': promoId});
    if ((res.data as Map)['success'] == true) {
      // optionally update local UI or refetch promos
      await fetchPromotionsReports();
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
