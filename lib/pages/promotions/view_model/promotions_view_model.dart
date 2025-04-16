import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/utils/phone_util.dart';

class PromotionsViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  double? whatsappPrice;
  double? smsPricePerSegment;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // -- TEMPLATES
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> get templates => _templates;

  bool _loadingTemplates = false;
  bool get loadingTemplates => _loadingTemplates;
  String shopName = '';

  // initialize pricing, e.g.:
  Future<void> initializePricing() async {
    final pricingService = await DynamicPricingService.initialize();
    whatsappPrice = pricingService.whatsappPromotionPrice;
    smsPricePerSegment = pricingService.smsReminderTemplatePrice;
    notifyListeners();
  }

  Future<void> fetchMessageShopName() async {
    try {
      shopName = await fetchShopName();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to fetch shop name: $e');
    }
  }

  Future<void> deleteTemplate(
      BuildContext context, String docID, Map<String, dynamic> template) async {
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Template deleted successfully')),
      );
    } catch (e) {
      debugPrint('Delete error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete template')),
      );
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
