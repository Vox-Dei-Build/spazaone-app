import 'dart:convert';

import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/twilio_proxy_client.dart';
import 'package:pasella/templates/sms_message.dart';
import 'package:pasella/utils/phone_util.dart';

class TwilioService {
  TwilioService._(this._proxy);

  final TwilioProxyClient _proxy;

  static Future<TwilioService> create() async {
    return TwilioService._(TwilioProxyClient());
  }

  String buildMediaJsonPath(String messagePath) {
    final raw = messagePath.split('.json').first;
    if (raw.endsWith('/Media.json')) return raw;
    return raw.endsWith('/') ? '${raw}Media.json' : '$raw/Media.json';
  }

  Future<List<String>> fetchMediaUrls(
    String mediaResourceUri, {
    required String customerId,
  }) async {
    final match =
        RegExp(r'/Messages/(SM[a-fA-F0-9]{32})').firstMatch(mediaResourceUri);
    if (match == null) return [];

    final response = await _proxy.post({
      'action': 'media',
      'messageSid': match.group(1),
      'customerId': customerId,
    });
    if (response.statusCode != 200) {
      throw Exception('Failed to load media: ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return List<String>.from(body['urls'] as List? ?? const []);
  }

  Future<List<Map<String, dynamic>>> fetchMessagesToCustomer({
    required String customerNumber,
    required String currentUserId,
    required String customerId,
  }) async {
    try {
      final results = await Future.wait([
        _fetchTwilioMessages(
          customerNumber: customerNumber,
          customerId: customerId,
          channel: 'sms',
          direction: 'to',
        ),
        _fetchTwilioMessages(
          customerNumber: customerNumber,
          customerId: customerId,
          channel: 'whatsapp',
          direction: 'to',
        ),
      ]);

      final allMessages = <Map<String, dynamic>>[
        ...results[0],
        ...results[1],
      ];

      for (final message in allMessages) {
        final messageText = (message['message'] ?? '').toString();
        final isWhatsApp = message['isWhatsApp'] == true;
        final isTemplateMessage = isWhatsApp
            ? await SMSMessages.isTemplateMessage(
                messageText,
                merchantId: currentUserId,
              )
            : true;
        if (!isTemplateMessage) message['isAI'] = true;
      }

      await _attachMedia(allMessages, customerId);
      allMessages.sort((a, b) =>
          (a['dateSent'] as DateTime).compareTo(b['dateSent'] as DateTime));
      return allMessages;
    } catch (error, stack) {
      await CrashService.instance.recordNonFatal(
        error,
        stack,
        reason: 'twilio fetchMessagesToCustomer failed',
      );
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchMessagesFromCustomer({
    required String customerNumber,
    required String customerId,
  }) async {
    try {
      final results = await Future.wait([
        _fetchTwilioMessages(
          customerNumber: customerNumber,
          customerId: customerId,
          channel: 'sms',
          direction: 'from',
        ),
        _fetchTwilioMessages(
          customerNumber: customerNumber,
          customerId: customerId,
          channel: 'whatsapp',
          direction: 'from',
        ),
      ]);

      final allMessages = <Map<String, dynamic>>[
        ...results[0],
        ...results[1],
      ];
      await _attachMedia(allMessages, customerId);
      allMessages.sort((a, b) =>
          (b['dateSent'] as DateTime).compareTo(a['dateSent'] as DateTime));
      return allMessages;
    } catch (error, stack) {
      await CrashService.instance.recordNonFatal(
        error,
        stack,
        reason: 'twilio fetchMessagesFromCustomer failed',
      );
      return [];
    }
  }

  Future<void> _attachMedia(
    List<Map<String, dynamic>> messages,
    String customerId,
  ) async {
    for (final message in messages) {
      message['num_media'] =
          int.tryParse((message['num_media'] ?? '0').toString()) ?? 0;
    }

    await Future.wait(
      messages.where((message) => (message['num_media'] as int) > 0).map(
        (message) async {
          final mediaUri = message['uri'] as String?;
          if (mediaUri == null || mediaUri.isEmpty) {
            message['mediaUrl'] = null;
            return;
          }
          try {
            final urls = await fetchMediaUrls(
              buildMediaJsonPath(mediaUri),
              customerId: customerId,
            );
            message['mediaUrl'] = urls.isNotEmpty ? urls.first : null;
          } catch (_) {
            message['mediaUrl'] = null;
          }
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchTwilioMessages({
    required String customerNumber,
    required String customerId,
    required String channel,
    required String direction,
  }) async {
    if (!isValidSAPhoneNumber(customerNumber)) return [];

    final response = await _proxy.post({
      'action': 'messages',
      'customerId': customerId,
      'channel': channel,
      'direction': direction,
    });
    if (response.statusCode != 200) {
      await CrashService.instance.recordNonFatal(
        'Twilio proxy returned ${response.statusCode}',
        StackTrace.current,
        reason: 'twilio history proxy error',
        context: {'status_code': response.statusCode},
      );
      return [];
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final messages = body['messages'] as List? ?? const [];
    return messages.map<Map<String, dynamic>>((raw) {
      final message = raw as Map<String, dynamic>;
      final parsedDate = DateTime.tryParse(
        (message['dateSent'] ?? '').toString(),
      );
      return {
        'sid': message['sid'],
        'message': message['body'],
        'dateSent': parsedDate ?? DateTime.now().toUtc(),
        'status': message['status'],
        'direction': direction == 'from' ? 'inbound' : 'outbound',
        'from': message['from'],
        'to': message['to'],
        'uri': message['uri'],
        'num_media': message['numMedia'] ?? 0,
        'isWhatsApp': channel == 'whatsapp',
      };
    }).toList();
  }
}
