import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/twilio_proxy_client.dart';

enum WhatsAppDeliveryOutcome { delivered, failed, unknown }

class WhatsAppMessagingService {
  final TwilioProxyClient _proxy;
  final Future<void> Function(Duration duration) _delay;

  WhatsAppMessagingService._(
    this._proxy, {
    Future<void> Function(Duration duration)? delay,
  }) : _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  static Future<WhatsAppMessagingService> create() async {
    return WhatsAppMessagingService._(TwilioProxyClient());
  }

  @visibleForTesting
  factory WhatsAppMessagingService.forTesting(
    TwilioProxyClient proxy, {
    Future<void> Function(Duration duration)? delay,
  }) {
    return WhatsAppMessagingService._(proxy, delay: delay);
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

  Future<WhatsAppDeliveryOutcome> pollMessageStatus(
    String messageSid, {
    int maxAttempts = 8,
  }) async {
    var delaySeconds = 1;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await _delay(Duration(seconds: delaySeconds));
      try {
        final response = await _proxy.post({
          'action': 'status',
          'messageSid': messageSid,
        });
        if (response.statusCode != 200) {
          await CrashService.instance.recordNonFatal(
            'WhatsApp status proxy returned ${response.statusCode}',
            StackTrace.current,
            reason: 'pollMessageStatus status unavailable',
            context: {'status_code': response.statusCode},
          );
          return WhatsAppDeliveryOutcome.unknown;
        }

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final status = body['status'] as String?;
        if (status == 'delivered' || status == 'read') {
          return WhatsAppDeliveryOutcome.delivered;
        }
        if (status == 'failed' ||
            status == 'undelivered' ||
            status == 'canceled') {
          return WhatsAppDeliveryOutcome.failed;
        }
        delaySeconds = delaySeconds < 60 ? delaySeconds * 2 : 60;
      } catch (error, stack) {
        await CrashService.instance.recordNonFatal(
          error,
          stack,
          reason: 'pollMessageStatus failed',
        );
        return WhatsAppDeliveryOutcome.unknown;
      }
    }

    await CrashService.instance.recordNonFatal(
      'WhatsApp delivery status did not reach a terminal state',
      StackTrace.current,
      reason: 'pollMessageStatus timed out',
      context: {'max_attempts': maxAttempts},
    );
    return WhatsAppDeliveryOutcome.unknown;
  }
}
