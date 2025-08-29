import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pasella/config/remote_config.dart';

/// Normalizes phone numbers for Botpress conversation tags:
/// Twilio/your app: +27XXXXXXXXX
/// Botpress tags:   27XXXXXXXXX  (no plus)
String normalizeMsisdnForBotpressTag(String e164) {
  if (e164.isEmpty) return e164;
  final digits = e164.replaceAll(RegExp(r'[^\d]'), '');
  // keep leading country code; for ZA this is 27
  return digits;
}

class BotpressService {
  BotpressService._(this._apiToken, this._botId) : _http = http.Client();

  final String _apiToken;
  final String _botId;
  final http.Client _http;

  static const _host = 'api.botpress.cloud';

  static Future<BotpressService> create() async {
    final rc = await RemoteConfigService.getInstance();
    final token = rc.getString('Botpress_Keys');
    final botId = rc.getString('BOTPRESS_BOT_ID');

    if (token.isEmpty || botId.isEmpty) {
      throw StateError(
          'Missing Remote Config: Botpress_Keys and/or BOTPRESS_BOT_ID');
    }
    return BotpressService._(token, botId);
  }

  void dispose() => _http.close();

  /// Public: fetch mapped messages for a customer number (E.164, e.g. +27…)
  Future<List<Map<String, dynamic>>> fetchBotpressMessages({
    required String customerNumber,
  }) async {
    try {
      final userPhoneNoPlus = normalizeMsisdnForBotpressTag(customerNumber);
      final conversationId = await _findConversationId(userPhoneNoPlus);
      if (conversationId == null) return const [];

      final raw = await _fetchMessages(conversationId);
      // Map to your app's message shape
      return raw.map<Map<String, dynamic>>((msg) {
        final payload = (msg['payload'] as Map?) ?? const {};
        final createdAtStr =
            (msg['createdAt'] ?? msg['created_at'])?.toString();
        final created = createdAtStr != null
            ? DateTime.parse(createdAtStr).toLocal()
            : DateTime.now();

        // Text prioritization
        final text = payload['text'] ??
            payload['value'] ??
            // Some Botpress payloads might be nested text in choice/others
            (payload['options'] != null ? '' : '') ??
            '';

        // Media extraction (Botpress standardizes *Url keys)
        String? mediaUrl;
        for (final key in const [
          'audioUrl',
          'imageUrl',
          'videoUrl',
          'fileUrl'
        ]) {
          if (payload[key] is String && (payload[key] as String).isNotEmpty) {
            mediaUrl = payload[key] as String;
            break;
          }
        }

        final direction = _normalizeDirection(msg['direction']);
        final tags = (msg['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
        final replyTo = tags['whatsapp:replyTo']?.toString();

        return {
          'id': msg['id'],
          'message': text?.toString() ?? '',
          'dateSent': created,
          'direction': direction, // 'inbound' | 'outbound'
          'isWhatsApp': true,
          'isSMS': false,
          'isAI': direction == 'outbound',
          'mediaUrl': mediaUrl,
          'bpTags': tags, // 👈 keep raw tags if you want
          'replyTo': replyTo, // 👈 convenience field
        };
      }).toList(growable: false);
    } catch (e, stack) {
      // Keep failures non-fatal to the UI
      // ignore: avoid_print
      print('🔥 Botpress fetch error: $e\n$stack');
      return const [];
    }
  }

  Future<String?> _findConversationId(String userPhoneNoPlus) async {
    String? nextToken;
    do {
      final uri = Uri.https(_host, '/v1/chat/conversations', {
        if (nextToken != null && nextToken.isNotEmpty) 'nextToken': nextToken,
      });

      final res = await _http.get(uri, headers: _headers());
      if (res.statusCode != 200) {
        // ignore: avoid_print
        print('❌ conversations ${res.statusCode}: ${res.body}');
        return null;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final conversations = (data['conversations'] as List?) ?? const [];
      for (final c in conversations) {
        final tags = (c is Map ? c['tags'] : null) as Map<String, dynamic>?;
        final tPhone = tags?['whatsapp:userPhone']?.toString();
        if (tPhone == userPhoneNoPlus) {
          return c['id']?.toString();
        }
      }
      nextToken = (data['meta'] as Map?)?['nextToken']?.toString();
    } while (nextToken != null && nextToken.isNotEmpty);

    return null;
  }

  Future<List<dynamic>> _fetchMessages(String conversationId) async {
    final all = <dynamic>[];
    String? nextToken;
    do {
      final uri = Uri.https(_host, '/v1/chat/messages', {
        'conversationId': conversationId,
        if (nextToken != null && nextToken.isNotEmpty) 'nextToken': nextToken,
      });
      final res = await _http.get(uri, headers: _headers());
      if (res.statusCode != 200) {
        // ignore: avoid_print
        print('❌ messages ${res.statusCode}: ${res.body}');
        break;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      all.addAll((data['messages'] as List?) ?? const []);
      nextToken = (data['meta'] as Map?)?['nextToken']?.toString();
    } while (nextToken != null && nextToken.isNotEmpty);
    return all;
  }

  Map<String, String> _headers() => {
        'Authorization': 'Bearer $_apiToken',
        'x-bot-id': _botId,
      };

  String _normalizeDirection(dynamic d) {
    final v = d?.toString().toLowerCase();
    if (v == 'incoming') return 'inbound';
    if (v == 'outgoing') return 'outbound';
    return v ?? '';
  }
}
