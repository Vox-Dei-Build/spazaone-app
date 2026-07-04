import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class RemoteConfigService {
  static RemoteConfigService? _instance;
  final FirebaseRemoteConfig _remoteConfig;

  RemoteConfigService._(this._remoteConfig);

  static Future<RemoteConfigService> getInstance() async {
    if (_instance == null) {
      final remoteConfig = FirebaseRemoteConfig.instance;
      try {
        await remoteConfig.setConfigSettings(
          RemoteConfigSettings(
            fetchTimeout: const Duration(seconds: 10),
            minimumFetchInterval: const Duration(
              hours: 1,
            ), // Prevents excessive fetching
          ),
        );
      } catch (e) {
        debugPrint("Failed to apply Remote Config settings: $e");
      }

      // Set defaults from environment variables
      try {
        await remoteConfig.setDefaults(<String, dynamic>{
          'TWILIO_ACCOUNT_SID': dotenv.env['TWILIO_ACCOUNT_SID'] ?? '',
          'TWILIO_AUTH_TOKEN': dotenv.env['TWILIO_AUTH_TOKEN'] ?? '',
          'TWILIO_NUMBER': dotenv.env['TWILIO_NUMBER'] ?? '',
          'TWILIO_MESSAGING_SERVICE_ID':
              dotenv.env['TWILIO_MESSAGING_SERVICE_ID'] ?? '',
          'TWILIO_ACCEPT_BNPL_TID': dotenv.env['TWILIO_ACCEPT_BNPL_TID'] ?? '',
          'TWILIO_REJECT_BNPL_TID': dotenv.env['TWILIO_REJECT_BNPL_TID'] ?? '',
          'TWILIO_ACCEPT_ORDER_TID':
              dotenv.env['TWILIO_ACCEPT_ORDER_TID'] ?? '',
          'TWILIO_REJECT_ORDER_TID':
              dotenv.env['TWILIO_REJECT_ORDER_TID'] ?? '',
          'TWILIO_ASSIGN_DRIVER_TID':
              dotenv.env['TWILIO_ASSIGN_DRIVER_TID'] ?? '',
          'TWILIO_MARK_OUT_FOR_DELIVERY_TID':
              dotenv.env['TWILIO_MARK_OUT_FOR_DELIVERY_TID'] ?? '',
          'TWILIO_MARK_DELIVERED_TID':
              dotenv.env['TWILIO_MARK_DELIVERED_TID'] ?? '',
          'TWILIO_MARK_CASH_RECEIVED_TID':
              dotenv.env['TWILIO_MARK_CASH_RECEIVED_TID'] ?? '',
          'TWILIO_MARK_COLLECTED_TID':
              dotenv.env['TWILIO_MARK_COLLECTED_TID'] ?? '',
          'TWILIO_SETTLE_BNPL_TID': dotenv.env['TWILIO_SETTLE_BNPL_TID'] ?? '',
          'TWILIO_CANCEL_ORDER_TID':
              dotenv.env['TWILIO_CANCEL_ORDER_TID'] ?? '',
          'WA_SUPPORT_NUMBER': dotenv.env['WA_SUPPORT_NUMBER'] ?? '',
          'USD_SMS_REMINDER_PRICE': dotenv.env['USD_SMS_REMINDER_PRICE'] ?? '0',
          'USD_SMS_PAYMENT_PRICE': dotenv.env['USD_SMS_PAYMENT_PRICE'] ?? '0',
          'USD_WHATSAPP_UTILITY_PRICE':
              dotenv.env['USD_WHATSAPP_UTILITY_PRICE'] ?? '0',
          'USD_WHATSAPP_PROMOTIONAL_PRICE':
              dotenv.env['USD_WHATSAPP_PROMOTIONAL_PRICE'] ?? '0',
          'MARKUP_SMS_PERCENTAGE': dotenv.env['MARKUP_SMS_PERCENTAGE'] ?? '0',
          'MARKUP_WHATSAPP_PERCENTAGE':
              dotenv.env['MARKUP_WHATSAPP_PERCENTAGE'] ?? '0',
          'MARKUP_PROMOTIONAL_PERCENTAGE':
              dotenv.env['MARKUP_PROMOTIONAL_PERCENTAGE'] ?? '0',
          'USD_ZAR_EXCHANGE_RATE':
              dotenv.env['USD_ZAR_EXCHANGE_RATE'] ?? '19.0',
          'PAYSTACK_LOCAL_PERCENT':
              dotenv.env['PAYSTACK_LOCAL_PERCENT'] ?? '2.9',
          'PAYSTACK_LOCAL_FLAT': dotenv.env['PAYSTACK_LOCAL_FLAT'] ?? '1.0',
          'PAYSTACK_EFT_PERCENT': dotenv.env['PAYSTACK_EFT_PERCENT'] ?? '2.0',
          'PAYSTACK_INT_PERCENT': dotenv.env['PAYSTACK_INT_PERCENT'] ?? '3.1',
          'PAYSTACK_INT_FLAT': dotenv.env['PAYSTACK_INT_FLAT'] ?? '1.0',
          'PAYSTACK_SETTLEMENT_FEE':
              dotenv.env['PAYSTACK_SETTLEMENT_FEE'] ?? '3.0',
          'PAYSTACK_VAT_PERCENT': dotenv.env['PAYSTACK_VAT_PERCENT'] ?? '15.0',
          // SMS template defaults — these mirror the production Remote Config
          // values (post-QW-0 with ASCII hyphens in the sign-off). Defaults
          // guarantee that if the RC fetch fails or a key is unset, the app
          // still has a non-empty SMS body to send instead of `''` (which
          // would hit Twilio with an empty `Body` parameter and either drop
          // silently or fail with a 400 depending on account config).
          // See `docs/openclaw/pas-sms-01-template-segment-audit.md` (QW-3).
          'SMS_CREDIT_CONFIRMATION_SHORT':
              'Hi {customerName}, transaction of -{amount} at {shopName} recorded. '
              'Balance: {balance}. Thanks for your trust. - {shopName}',
          'SMS_PAYMENT_CONFIRMATION_SHORT':
              'Hi {customerName}, payment of +{amount} at {shopName} recorded. '
              'Balance: {balance}. Thanks for your payment. - {shopName}',
          'SMS_ONBOARDING_SHORT':
              'Hi {customerName}, welcome to {shopName}! Your account is now '
              'online. Balance: R0,00. Thanks for joining! - {shopName}',
          'SMS_REMINDER_SHORT':
              'Hi {customerName}, your balance of {balance} at {shopName} is '
              'due. Please make your payment to avoid any late fees. From '
              '{shopName}',
          'SMS_TEMPLATE_KEYWORDS': '[]',
          'FEATURE_NUMBER_FIRST_ONBOARDING_ENABLED':
              dotenv.env['FEATURE_NUMBER_FIRST_ONBOARDING_ENABLED'] == 'true',
          'FEATURE_DEFER_AUTH_CONSENT_ENABLED':
              dotenv.env['FEATURE_DEFER_AUTH_CONSENT_ENABLED'] == 'true',
          'FEATURE_OTP_AUTOSUBMIT_ENABLED':
              dotenv.env['FEATURE_OTP_AUTOSUBMIT_ENABLED'] == 'true',
          'FEATURE_OTP_RESEND_IN_DIALOG_ENABLED':
              dotenv.env['FEATURE_OTP_RESEND_IN_DIALOG_ENABLED'] == 'true',
        });
      } catch (e) {
        debugPrint("Failed to apply Remote Config defaults: $e");
      }

      _instance = RemoteConfigService._(remoteConfig);
      await _instance!
          ._initialize(); // Ensures Remote Config is ready before use
    }
    return _instance!;
  }

  Future<void> _initialize() async {
    try {
      await _remoteConfig.fetchAndActivate();
      if (!kIsWeb) {
        _remoteConfig.onConfigUpdated.listen(
          (event) async {
            try {
              await _remoteConfig.activate();
              debugPrint("Remote config updated and activated.");
            } catch (e) {
              debugPrint("Failed to activate Remote Config update: $e");
            }
          },
          onError: (Object e) {
            debugPrint("Remote Config update listener failed: $e");
          },
        );
      }
    } catch (e) {
      debugPrint("Failed to fetch and activate Remote Config: $e");
    }
  }

  String getString(String key) {
    return _remoteConfig.getString(key);
  }

  double getDouble(String key, {double defaultValue = 0.0}) {
    return _remoteConfig.getDouble(key) == 0.0
        ? double.tryParse(_remoteConfig.getString(key)) ?? defaultValue
        : _remoteConfig.getDouble(key);
  }

  bool getBool(String key, {bool defaultValue = false}) {
    final value = _remoteConfig.getValue(key);
    if (value.source == ValueSource.valueStatic) {
      return defaultValue;
    }
    return value.asBool();
  }
}
