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
        final payload = (msg['payload'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final createdAtStr =
            (msg['createdAt'] ?? msg['created_at'])?.toString();
        final created = createdAtStr != null
            ? DateTime.parse(createdAtStr).toLocal()
            : DateTime.now();

        // PAS-AI-02: full Botpress payload coverage. Previously only `text` /
        // `value` were extracted, so `card`, `carousel`, `choice`, `dropdown`,
        // `markdown`, `bloc`, `location` payloads rendered as blank bubbles in
        // the Connect tab. Merchants saw nothing when the bot replied to a
        // menu selection with anything other than a plain `text` message.
        final text = _renderPayloadText(payload);

        // Media extraction (Botpress standardizes *Url keys); now also looks
        // inside `bloc` items and `card` images.
        final mediaUrl = _extractMediaUrl(payload);

        final direction = _normalizeDirection(msg['direction']);
        final tags = (msg['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
        final replyTo = tags['whatsapp:replyTo']?.toString();
        final payloadType = payload['type']?.toString();

        return {
          'id': msg['id'],
          'message': text,
          'dateSent': created,
          'direction': direction, // 'inbound' | 'outbound'
          'isWhatsApp': true,
          'isSMS': false,
          'isAI': direction == 'outbound',
          'mediaUrl': mediaUrl,
          'bpTags': tags, // 👈 keep raw tags if you want
          'replyTo': replyTo, // 👈 convenience field
          // PAS-AI-02: expose the structured payload + its type so the chat
          // bubble can render menu options / cards instead of a blank string.
          'payloadType': payloadType,
          'payload': payload,
        };
      }).toList(growable: false);
    } catch (e, stack) {
      // Keep failures non-fatal to the UI
      // ignore: avoid_print
      print('🔥 Botpress fetch error: $e\n$stack');
      return const [];
    }
  }

  /// Renders a human-readable string for any Botpress chat payload type.
  ///
  /// Handles every variant the Botpress Chat API can return on the WhatsApp
  /// channel: `text`, `markdown`, `choice`, `dropdown`, `card`, `carousel`,
  /// `bloc`, `location`, `image`/`audio`/`video`/`file` (caption fallback).
  /// Unknown types return empty so the UI can decide whether to drop them.
  String _renderPayloadText(Map<String, dynamic> payload) {
    if (payload.isEmpty) return '';
    final type = payload['type']?.toString();

    // Plain text wins regardless of type if present.
    final directText = payload['text'];
    if (directText is String && directText.trim().isNotEmpty) {
      // For choice/dropdown also append the labelled options so the merchant
      // can see what the bot actually offered the customer.
      if (type == 'choice' || type == 'dropdown') {
        final options = (payload['options'] as List?) ?? const [];
        if (options.isEmpty) return directText;
        final lines = <String>[directText];
        for (var i = 0; i < options.length; i++) {
          final o = options[i];
          if (o is Map) {
            final label = (o['label'] ?? o['value'] ?? '').toString();
            if (label.isNotEmpty) lines.add('${i + 1}. $label');
          }
        }
        return lines.join('\n');
      }
      return directText;
    }

    // Markdown body.
    final markdown = payload['markdown'];
    if (markdown is String && markdown.trim().isNotEmpty) return markdown;

    // Inbound choice replies: the chosen option lands in `value`.
    final value = payload['value'];
    if (value is String && value.trim().isNotEmpty) return value;

    switch (type) {
      case 'card':
        return _renderCard(payload);
      case 'carousel':
        final items = (payload['items'] as List?) ?? const [];
        return items
            .whereType<Map>()
            .map((c) => _renderCard(c.cast<String, dynamic>()))
            .where((s) => s.isNotEmpty)
            .join('\n\n');
      case 'bloc':
        final items = (payload['items'] as List?) ?? const [];
        return items
            .whereType<Map>()
            .map((it) => _renderPayloadText(it.cast<String, dynamic>()))
            .where((s) => s.isNotEmpty)
            .join('\n');
      case 'location':
        final addr = payload['address']?.toString();
        final title = payload['title']?.toString();
        final lat = payload['latitude'];
        final lon = payload['longitude'];
        final parts = <String>[
          if (title != null && title.isNotEmpty) title,
          if (addr != null && addr.isNotEmpty) addr,
          if (lat != null && lon != null) '($lat, $lon)',
        ];
        return parts.isEmpty ? '📍 Location shared' : '📍 ${parts.join(' · ')}';
      case 'image':
        return (payload['title'] as String?)?.trim().isNotEmpty == true
            ? payload['title'] as String
            : '';
      case 'audio':
        return '🎵 Audio message';
      case 'video':
        return '🎬 Video message';
      case 'file':
        final title = (payload['title'] as String?)?.trim();
        return (title?.isNotEmpty ?? false) ? '📎 $title' : '📎 File';
    }

    return '';
  }

  String _renderCard(Map<String, dynamic> card) {
    final title = (card['title'] as String?)?.trim() ?? '';
    final subtitle = (card['subtitle'] as String?)?.trim() ?? '';
    final actions = (card['actions'] as List?) ?? const [];
    final lines = <String>[
      if (title.isNotEmpty) title,
      if (subtitle.isNotEmpty) subtitle,
    ];
    if (actions.isNotEmpty) {
      for (var i = 0; i < actions.length; i++) {
        final a = actions[i];
        if (a is Map) {
          final label = (a['label'] ?? a['value'] ?? '').toString();
          if (label.isNotEmpty) lines.add('${i + 1}. $label');
        }
      }
    }
    return lines.join('\n');
  }

  String? _extractMediaUrl(Map<String, dynamic> payload) {
    for (final key in const ['audioUrl', 'imageUrl', 'videoUrl', 'fileUrl']) {
      final v = payload[key];
      if (v is String && v.isNotEmpty) return v;
    }
    // `card` carries imageUrl; `bloc` may carry a media child.
    if (payload['type'] == 'card') {
      final v = payload['imageUrl'];
      if (v is String && v.isNotEmpty) return v;
    }
    if (payload['type'] == 'bloc') {
      final items = (payload['items'] as List?) ?? const [];
      for (final it in items) {
        if (it is Map) {
          final found = _extractMediaUrl(it.cast<String, dynamic>());
          if (found != null && found.isNotEmpty) return found;
        }
      }
    }
    return null;
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
