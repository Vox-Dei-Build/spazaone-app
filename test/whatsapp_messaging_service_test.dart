import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/services/twilio_proxy_client.dart';
import 'package:pasella/services/whatsapp_messaging_service.dart';

TwilioProxyClient proxyReturning(http.Response response) {
  return TwilioProxyClient(
    idTokenProvider: () async => 'firebase-id-token',
    appCheckTokenProvider: () async => 'firebase-app-check-token',
    httpClient: MockClient((_) async => response),
  );
}

WhatsAppMessagingService serviceReturning(http.Response response) {
  return WhatsAppMessagingService.forTesting(
    proxyReturning(response),
    delay: (_) async {},
  );
}

void main() {
  group('WhatsApp delivery polling', () {
    test('treats delivered and read as successful terminal statuses', () async {
      for (final status in ['delivered', 'read']) {
        final service = serviceReturning(
          http.Response(jsonEncode({'status': status}), 200),
        );

        expect(
          await service.pollMessageStatus('SM${'a' * 32}'),
          WhatsAppDeliveryOutcome.delivered,
        );
      }
    });

    test('returns failed only for definitive provider failures', () async {
      for (final status in ['failed', 'undelivered', 'canceled']) {
        final service = serviceReturning(
          http.Response(jsonEncode({'status': status}), 200),
        );

        expect(
          await service.pollMessageStatus('SM${'b' * 32}'),
          WhatsAppDeliveryOutcome.failed,
        );
      }
    });

    test('keeps a status lookup HTTP error unknown', () async {
      final service = serviceReturning(http.Response('{}', 503));

      expect(
        await service.pollMessageStatus('SM${'c' * 32}'),
        WhatsAppDeliveryOutcome.unknown,
      );
    });

    test('keeps a non-terminal status unknown after polling limit', () async {
      final service = serviceReturning(
        http.Response(jsonEncode({'status': 'sent'}), 200),
      );

      expect(
        await service.pollMessageStatus('SM${'d' * 32}', maxAttempts: 1),
        WhatsAppDeliveryOutcome.unknown,
      );
    });
  });

  group('SMS fallback policy', () {
    test('falls back only after a definitive WhatsApp failure', () {
      expect(
        MessagingNotificationService.shouldFallbackToSmsForStatus(
          WhatsAppDeliveryOutcome.failed,
        ),
        isTrue,
      );
      expect(
        MessagingNotificationService.shouldFallbackToSmsForStatus(
          WhatsAppDeliveryOutcome.delivered,
        ),
        isFalse,
      );
      expect(
        MessagingNotificationService.shouldFallbackToSmsForStatus(
          WhatsAppDeliveryOutcome.unknown,
        ),
        isFalse,
      );
    });
  });
}
