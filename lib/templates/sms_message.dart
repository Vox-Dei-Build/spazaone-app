import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/services/template_service.dart';

class SMSMessages {
  // The four `_SHORT` strings are the only SMS bodies the client actually
  // sends. The corresponding non-`_SHORT` RC keys (SMS_CREDIT_CONFIRMATION,
  // SMS_PAYMENT_CONFIRMATION, SMS_ONBOARDING, SMS_REMINDER) were previously
  // loaded into matching fields here but never read anywhere — dead state
  // that misled engineers attempting to fix copy via the long key. Removed
  // 2026-05-10 alongside the matching deletion of those long keys in
  // Firebase Remote Config (QW-5 in pas-sms-01-template-segment-audit).
  static String creditConfirmationShort = '';
  static String paymentConfirmationShort = '';
  static String onboardingShort = '';
  static String reminderShort = '';
  static List<String> templateKeywords = [];
  static bool _remoteConfigLoaded = false;

  static Future<void> loadTemplates({String? merchantId}) async {
    final rc = await RemoteConfigService.getInstance();
    final keywordsJson = rc.getString('SMS_TEMPLATE_KEYWORDS');

    creditConfirmationShort = rc.getString('SMS_CREDIT_CONFIRMATION_SHORT');
    paymentConfirmationShort = rc.getString('SMS_PAYMENT_CONFIRMATION_SHORT');
    onboardingShort = rc.getString('SMS_ONBOARDING_SHORT');
    reminderShort = rc.getString('SMS_REMINDER_SHORT');
    await TemplateService().loadTemplatesFromFirestore(merchantId: merchantId);
    _remoteConfigLoaded = true;

    try {
      templateKeywords = List<String>.from(jsonDecode(keywordsJson));
    } catch (e) {
      debugPrint('Failed to parse template keywords: $e');
      templateKeywords = [];
    }
  }

  static Future<bool> isTemplateMessage(
    String messageText, {
    String? merchantId,
  }) async {
    final resolvedMerchantId =
        (merchantId?.trim().isNotEmpty ?? false)
            ? merchantId!.trim()
            : FirebaseAuth.instance.currentUser?.uid;

    if (!_remoteConfigLoaded) {
      await loadTemplates(merchantId: resolvedMerchantId);
    } else {
      await TemplateService().loadTemplatesFromFirestore(
        merchantId: resolvedMerchantId,
      );
    }

    final keywordMatch = templateKeywords.any(
      (keyword) => messageText.toLowerCase().contains(keyword.toLowerCase()),
    );

    final merchantTemplateMatch = TemplateService()
        .isMatchWithMerchantTemplates(messageText);

    return keywordMatch || merchantTemplateMatch;
  }
}
