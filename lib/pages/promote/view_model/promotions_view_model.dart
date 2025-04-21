import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:http/http.dart' as http;

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

  // -- TEMPLATES
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> get templates => _templates;

  bool _loadingTemplates = false;
  bool get loadingTemplates => _loadingTemplates;
  String shopName = '';

  Map<String, dynamic> promoBreakdown = {};

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
    return ((text).length / 160).ceil();
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

  Future<void> sendPromotion({
    required String templateId,
    required List<String> customerIds,
    required Map<String, String> variables,
    required bool testMode,
  }) async {
    _sendingPromotion = true;
    notifyListeners();

    try {
      // Cloud Function call or Firestore write for queued promo
      final response =
          await FirebaseFirestore.instance.collection('promotions').add({
        'templateId': templateId,
        'customerIds': customerIds,
        'variables': variables,
        'testMode': testMode,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Promotion queued: ${response.id}');
    } catch (e) {
      debugPrint('Failed to send promotion: $e');
    } finally {
      _sendingPromotion = false;
      notifyListeners();
    }
  }

  Future<void> runPromotion(
      String merchantId, List<String> customerIds, String templateId) async {
    final response = await http.post(
      Uri.parse(
          "https://us-central1-pasella-ledger.cloudfunctions.net/runMerchantPromotion"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "merchantId": merchantId,
        "customerIds": customerIds,
        "templateId": templateId,
      }),
    );

    if (response.statusCode == 200) {
      // handle success
    } else {
      // handle failure
    }
  }

  // -- REPORTS (Simplified)
  Future<List<Map<String, dynamic>>> fetchPromotionsReports(
      String userId) async {
    try {
      final snapshot = await _firestore
          .collection('promotions')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Failed to fetch promotion reports: $e');
      return [];
    }
  }
}
