import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/twilio_proxy_client.dart';

class WhatsAppMessagingService {
  final TwilioProxyClient _proxy;

  WhatsAppMessagingService._(this._proxy);

  static Future<WhatsAppMessagingService> create() async {
    return WhatsAppMessagingService._(TwilioProxyClient());
  }

  @visibleForTesting
  factory WhatsAppMessagingService.forTesting(TwilioProxyClient proxy) {
    return WhatsAppMessagingService._(proxy);
  }

  Future<String?> sendWhatsAppMessage(
    String to,
    String templateSid,
    Map<String, dynamic> variables,
  ) async {
    try {
      final response = await _proxy.post({
        'action': 'send',
        'channel': 'whatsapp',
        'to': to,
        'templateId': templateSid,
        'templateParams': variables,
        'botType': 'Customer',
      });

      if (response.statusCode == 201) {
        final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
        return responseBody['sid'] as String?;
      }

      await CrashService.instance.recordNonFatal(
        'WhatsApp proxy returned ${response.statusCode}',
        StackTrace.current,
        reason: 'sendWhatsAppMessage proxy error',
        context: {'status_code': response.statusCode},
      );
      return null;
    } catch (error, stack) {
      await CrashService.instance.recordNonFatal(
        error,
        stack,
        reason: 'sendWhatsAppMessage failed',
      );
      return null;
    }
  }

  Future<bool> pollMessageStatus(String messageSid) async {
    var delaySeconds = 1;
    while (true) {
      await Future.delayed(Duration(seconds: delaySeconds));
      try {
        final response = await _proxy.post({
          'action': 'status',
          'messageSid': messageSid,
        });
        if (response.statusCode != 200) return false;

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final status = body['status'] as String?;
        if (status == 'delivered') return true;
        if (status == 'failed' ||
            status == 'undelivered' ||
            status == 'canceled') {
          return false;
        }
        delaySeconds = delaySeconds < 60 ? delaySeconds * 2 : 60;
      } catch (error, stack) {
        await CrashService.instance.recordNonFatal(
          error,
          stack,
          reason: 'pollMessageStatus failed',
        );
        return false;
      }
    }
  }
}
