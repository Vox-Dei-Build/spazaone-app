import 'package:cloud_firestore/cloud_firestore.dart';

class TemplateService {
  static final TemplateService _instance = TemplateService._internal();
  factory TemplateService() => _instance;
  TemplateService._internal();

  List<Map<String, dynamic>> _templates = [];

  Future<void> loadTemplatesFromFirestore() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('messagingTemplates')
        .where('active', isEqualTo: true)
        .get();

    _templates = snapshot.docs.map((doc) => doc.data()).toList();
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
