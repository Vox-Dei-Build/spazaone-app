import 'package:flutter/foundation.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/twilio_proxy_client.dart';

class SMSMessagingService {
  final TwilioProxyClient _proxy;

  SMSMessagingService._(this._proxy);

  static Future<SMSMessagingService> create() async {
    return SMSMessagingService._(TwilioProxyClient());
  }

  @visibleForTesting
  factory SMSMessagingService.forTesting(TwilioProxyClient proxy) {
    return SMSMessagingService._(proxy);
  }

  Future<int> sendSMS(String phoneNumber, String message) async {
    try {
      final response = await _proxy.post({
        'action': 'send',
        'channel': 'sms',
        'to': phoneNumber,
        'body': message,
      });
      return response.statusCode;
    } catch (error, stack) {
      await CrashService.instance.recordNonFatal(
        error,
        stack,
        reason: 'sendSMS failed',
      );
      return 503;
    }
  }
}
