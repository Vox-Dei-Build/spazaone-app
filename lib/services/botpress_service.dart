import 'dart:convert';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:pasella/services/store_session.dart';
import 'package:pasella/config/function_endpoints.dart';

class BotpressConversationException implements Exception {
  const BotpressConversationException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class BotpressService {
  BotpressService._() : _http = http.Client();

  final http.Client _http;

  static Uri get _endpoint => FunctionEndpoints.https('getBotpressMessages');

  static Future<BotpressService> create() async {
    return BotpressService._();
  }

  void dispose() => _http.close();

  /// Fetch mapped messages for a merchant-owned customer thread.
  Future<List<Map<String, dynamic>>> fetchBotpressMessages({
    required String customerId,
  }) async {
    try {
      final raw = await _fetchMessages(customerId);
      // Map to your app's message shape
      return raw.map<Map<String, dynamic>>((msg) {
        final payload = (msg['payload'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final createdAtStr =
            (msg['createdAt'] ?? msg['created_at'])?.toString();
        final created = createdAtStr == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.tryParse(createdAtStr)?.toLocal() ??
                DateTime.fromMillisecondsSinceEpoch(0);

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
    } on BotpressConversationException {
      rethrow;
    } catch (error, stack) {
      // Structured, non-secret diagnostic; the ViewModel keeps Twilio and the
      // Firestore truth surface visible while showing a human fallback.
      // ignore: avoid_print
      print('[botpress] MESSAGE_MAPPING_FAILED: $error\n$stack');
      throw const BotpressConversationException(
        'BOTPRESS_MESSAGE_MAPPING_FAILED',
        'Bot conversation history could not be read. Other message history is still available.',
      );
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

  Future<List<dynamic>> _fetchMessages(String customerId) async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    final appCheckToken = await FirebaseAppCheck.instance.getToken();
    if (idToken == null ||
        idToken.isEmpty ||
        appCheckToken == null ||
        appCheckToken.isEmpty) {
      throw StateError('Verified merchant session required.');
    }

    final response = await _http.post(
      _endpoint,
      headers: {
        'Authorization': 'Bearer $idToken',
        'X-Firebase-AppCheck': appCheckToken,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'customerId': customerId,
        'storeId': StoreSession.instance.storeId,
      }),
    );
    if (response.statusCode != 200) {
      Map<String, dynamic> body = const {};
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      final diagnostic = body['diagnostic'] is Map
          ? Map<String, dynamic>.from(body['diagnostic'] as Map)
          : const <String, dynamic>{};
      throw BotpressConversationException(
        diagnostic['code']?.toString() ?? 'BOTPRESS_PROXY_UNAVAILABLE',
        'Bot conversation history is temporarily unavailable. Other message history is still shown.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['state'] == 'not_found') {
      throw const BotpressConversationException(
        'BOTPRESS_CONVERSATION_NOT_FOUND',
        'No bot conversation was found for this customer. Other message history is still shown.',
      );
    }
    return body['messages'] as List? ?? const [];
  }

  String _normalizeDirection(dynamic d) {
    final v = d?.toString().toLowerCase();
    if (v == 'incoming') return 'inbound';
    if (v == 'outgoing') return 'outbound';
    return v ?? '';
  }
}
