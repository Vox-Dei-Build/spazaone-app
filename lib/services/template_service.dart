import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TemplateService {
  static final TemplateService _instance = TemplateService._internal();
  factory TemplateService() => _instance;
  TemplateService._internal();

  List<Map<String, dynamic>> _templates = [];
  String? _loadedMerchantId;
  bool _hasLoadedTemplates = false;

  Future<void> loadTemplatesFromFirestore({
    String? merchantId,
    bool force = false,
  }) async {
    final resolvedMerchantId =
        (merchantId?.trim().isNotEmpty ?? false)
            ? merchantId!.trim()
            : FirebaseAuth.instance.currentUser?.uid;

    if (resolvedMerchantId == null || resolvedMerchantId.isEmpty) {
      _templates = [];
      _loadedMerchantId = null;
      _hasLoadedTemplates = true;
      return;
    }

    if (!force &&
        _hasLoadedTemplates &&
        _loadedMerchantId == resolvedMerchantId) {
      return;
    }

    final snapshot =
        await FirebaseFirestore.instance
            .collection('messagingTemplates')
            .where('userId', isEqualTo: resolvedMerchantId)
            .where('active', isEqualTo: true)
            .get();

    _templates =
        snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
    _loadedMerchantId = resolvedMerchantId;
    _hasLoadedTemplates = true;
  }

  bool isMatchWithMerchantTemplates(String messageText) {
    final normalizedMessage = _normalize(messageText);

    return _templates.any((template) {
      final whatsappContent =
          template['channels']?['whatsapp']?['templateContent'] ?? '';
      final smsContent = template['channels']?['sms']?['templateContent'] ?? '';

      final whatsappPattern = RegExp(
        _normalize(_replaceVariablesWithWildcard(whatsappContent)),
        caseSensitive: false,
      );
      final smsPattern = RegExp(
        _normalize(_replaceVariablesWithWildcard(smsContent)),
        caseSensitive: false,
      );

      return whatsappPattern.hasMatch(normalizedMessage) ||
          smsPattern.hasMatch(normalizedMessage);
    });
  }

  String _replaceVariablesWithWildcard(String text) {
    return text.replaceAllMapped(RegExp(r'{{.*?}}'), (match) => '.*');
  }

  String _normalize(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
