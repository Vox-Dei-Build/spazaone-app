import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/utils/phone_util.dart';

class BotpressService {
  BotpressService._(this._apiToken, this._botId) : _http = http.Client();

  final String _apiToken;
  final String _botId;
  final http.Client _http;

  static Future<BotpressService> create() async {
    final remoteConfigService = await RemoteConfigService.getInstance();
    final token = remoteConfigService.getString('Botpress_Keys');
    final botId = remoteConfigService.getString('BOTPRESS_BOT_ID');
    return BotpressService._(token, botId);
  }

  void dispose() {
    _http.close();
  }

  Future<List<Map<String, dynamic>>> fetchBotpressMessages({
    required String customerNumber,
  }) async {
    try {
      final normalizedNumber = formatPhoneNumberForWhatsapp(customerNumber);
      final conversationId = await _findConversationId(normalizedNumber);
      if (conversationId == null) return [];
      final rawMessages = await _fetchMessages(conversationId);
      return rawMessages.map<Map<String, dynamic>>((msg) {
        final createdAt = msg['createdAt'] ?? msg['created_at'];
        final direction = _normalizeDirection(msg['direction']);
        final payload = msg['payload'] ?? {};
        final text = payload['text'] ?? payload['value'] ?? '';
        String? mediaUrl;
        if (payload['audioUrl'] != null) {
          mediaUrl = payload['audioUrl'];
        } else if (payload['imageUrl'] != null) {
          mediaUrl = payload['imageUrl'];
        } else if (payload['videoUrl'] != null) {
          mediaUrl = payload['videoUrl'];
        } else if (payload['fileUrl'] != null) {
          mediaUrl = payload['fileUrl'];
        }
        return {
          'id': msg['id'],
          'message': text,
          'dateSent': createdAt != null
              ? DateTime.parse(createdAt.toString())
              : DateTime.now(),
          'direction': direction,
          'isWhatsApp': true,
          'isSMS': false,
          'isAI': direction == 'outbound',
          'mediaUrl': mediaUrl,
        };
      }).toList();
    } catch (e, stack) {
      print('🔥 Error fetching Botpress messages: $e');
      print('📜 StackTrace: $stack');
      return [];
    }
  }

  Future<String?> _findConversationId(String userPhone) async {
    String? nextToken;
    do {
      final uri = Uri.https('api.botpress.cloud', '/v1/chat/conversations', {
        if (nextToken != null) 'nextToken': nextToken,
      });
      final response = await _http.get(uri, headers: {
        'Authorization': 'Bearer $_apiToken',
        'x-bot-id': _botId,
      });
      if (response.statusCode != 200) {
        print('❌ Conversation fetch error: ${response.statusCode}');
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final conversations = (data['conversations'] ?? []) as List<dynamic>;
      for (final conv in conversations) {
        if (conv is Map<String, dynamic>) {
          final tags = conv['tags'] as Map<String, dynamic>?;
          if (tags != null && tags['whatsapp:userPhone'] == userPhone) {
            return conv['id'] as String?;
          }
        }
      }
      nextToken = data['meta']?['nextToken'];
    } while (nextToken != null && nextToken!.isNotEmpty);
    return null;
  }

  Future<List<dynamic>> _fetchMessages(String conversationId) async {
    final messages = <dynamic>[];
    String? nextToken;
    do {
      final uri = Uri.https('api.botpress.cloud', '/v1/chat/messages', {
        'conversationId': conversationId,
        if (nextToken != null) 'nextToken': nextToken,
      });
      final response = await _http.get(uri, headers: {
        'Authorization': 'Bearer $_apiToken',
        'x-bot-id': _botId,
      });
      if (response.statusCode != 200) {
        print('❌ Message fetch error: ${response.statusCode}');
        break;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      messages.addAll(data['messages'] ?? []);
      nextToken = data['meta']?['nextToken'];
    } while (nextToken != null && nextToken!.isNotEmpty);
    return messages;
  }

  String _normalizeDirection(dynamic direction) {
    switch (direction) {
      case 'incoming':
        return 'inbound';
      case 'outgoing':
        return 'outbound';
      default:
        return direction?.toString() ?? '';
    }
  }
}

