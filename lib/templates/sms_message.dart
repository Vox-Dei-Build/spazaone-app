import 'dart:convert';

import 'package:pasella/config/remote_config.dart';

class SMSMessages {
  static String creditConfirmation = '';
  static String paymentConfirmation = '';
  static String onboarding = '';
  static String reminder = '';

  static String creditConfirmationShort = '';
  static String paymentConfirmationShort = '';
  static String onboardingShort = '';
  static String reminderShort = '';
  static List<String> templateKeywords = [];

  static Future<void> loadTemplates() async {
    final rc = await RemoteConfigService.getInstance();
    final keywordsJson = rc.getString('SMS_TEMPLATE_KEYWORDS');

    creditConfirmation = rc.getString('SMS_CREDIT_CONFIRMATION');
    paymentConfirmation = rc.getString('SMS_PAYMENT_CONFIRMATION');
    onboarding = rc.getString('SMS_ONBOARDING');
    reminder = rc.getString('SMS_REMINDER');

    creditConfirmationShort = rc.getString('SMS_CREDIT_CONFIRMATION_SHORT');
    paymentConfirmationShort = rc.getString('SMS_PAYMENT_CONFIRMATION_SHORT');
    onboardingShort = rc.getString('SMS_ONBOARDING_SHORT');
    reminderShort = rc.getString('SMS_REMINDER_SHORT');

    try {
      templateKeywords = List<String>.from(jsonDecode(keywordsJson));
    } catch (e) {
      print('⚠️ Failed to parse template keywords: $e');
      templateKeywords = [];
    }
  }

  static bool isTemplateMessage(String messageText) {
    return templateKeywords.any(
      (keyword) => messageText.toLowerCase().contains(keyword.toLowerCase()),
    );
  }
}
