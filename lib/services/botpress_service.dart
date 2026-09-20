import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pasella/config/function_endpoints.dart';
import 'package:pasella/models/conversation/conversation_presentation.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/secure_function_client.dart';

class BotpressConversationException implements Exception {
  const BotpressConversationException(
    this.code,
    this.message, {
    required this.stage,
    this.retryOutcome = 'not_attempted',
  });

  final String code;
  final String message;
  final String stage;
  final String retryOutcome;

  @override
  String toString() => message;
}

class BotpressConversationWarning {
  const BotpressConversationWarning({
    required this.code,
    required this.message,
    required this.stage,
    this.skippedMessageCount = 0,
  });

  final String code;
  final String message;
  final String stage;
  final int skippedMessageCount;
}

class BotpressConversationResult {
  const BotpressConversationResult({
    required this.messages,
    this.warning,
  });

  final List<Map<String, dynamic>> messages;
  final BotpressConversationWarning? warning;

  String? get warningCode => warning?.code;
  int get skippedMessageCount => warning?.skippedMessageCount ?? 0;
}

class _BotpressEnvelope {
  const _BotpressEnvelope({
    required this.messages,
    this.notFound = false,
    this.serverSkippedMessageCount = 0,
    this.retryOutcome = 'not_needed',
  });

  final List<dynamic> messages;
  final bool notFound;
  final int serverSkippedMessageCount;
  final String retryOutcome;
}

class BotpressService {
  BotpressService._(this._client, this._endpoint);

  final SecureFunctionClient _client;
  final Uri _endpoint;

  static Future<BotpressService> create() async {
    return BotpressService._(
      SecureFunctionClient(),
      FunctionEndpoints.https('getBotpressMessages'),
    );
  }

  @visibleForTesting
  factory BotpressService.forTesting(
    SecureFunctionClient client, {
    Uri? endpoint,
  }) {
    return BotpressService._(
      client,
      endpoint ?? Uri.parse('https://example.test/getBotpressMessages'),
    );
  }

  void dispose() => _client.close();

  /// Fetch mapped messages for a merchant-owned customer thread.
  Future<BotpressConversationResult> fetchBotpressMessages({
    required String customerId,
  }) async {
    try {
      final envelope = await _fetchMessages(customerId);
      if (envelope.notFound) {
        if (envelope.retryOutcome != 'not_needed') {
          await _recordRetry(envelope.retryOutcome);
        }
        return const BotpressConversationResult(messages: []);
      }

      final messages = <Map<String, dynamic>>[];
      var skippedMessageCount = envelope.serverSkippedMessageCount;
      for (final rawMessage in envelope.messages) {
        if (rawMessage is! Map) {
          skippedMessageCount++;
          continue;
        }
        try {
          messages.add(_mapMessage(Map<String, dynamic>.from(rawMessage)));
        } catch (_) {
          skippedMessageCount++;
        }
      }

      BotpressConversationWarning? warning;
      if (skippedMessageCount > 0) {
        warning = BotpressConversationWarning(
          code: 'BOTPRESS_MESSAGES_PARTIAL',
          stage: 'mapping',
          skippedMessageCount: skippedMessageCount,
          message:
              'Some bot messages could not be displayed. Other message history is still available.',
        );
        await _recordFailure(
          warning.code,
          warning.stage,
          skippedMessageCount: skippedMessageCount,
          retryOutcome: envelope.retryOutcome,
        );
      } else if (envelope.retryOutcome != 'not_needed') {
        await _recordRetry(envelope.retryOutcome);
      }
      return BotpressConversationResult(messages: messages, warning: warning);
    } on BotpressConversationException catch (error, stack) {
      await _recordFailure(
        error.code,
        error.stage,
        stack: stack,
        retryOutcome: error.retryOutcome,
      );
      return BotpressConversationResult(
        messages: const [],
        warning: BotpressConversationWarning(
          code: error.code,
          message: error.message,
          stage: error.stage,
        ),
      );
    } catch (error, stack) {
      await _recordFailure(
        'BOTPRESS_REQUEST_FAILED',
        'unknown',
        stack: stack,
      );
      return const BotpressConversationResult(
        messages: [],
        warning: BotpressConversationWarning(
          code: 'BOTPRESS_REQUEST_FAILED',
          stage: 'unknown',
          message:
              'Bot conversation history is temporarily unavailable. Retry to load it again.',
        ),
      );
    }
  }

  Map<String, dynamic> _mapMessage(Map<String, dynamic> msg) {
    final id = msg['id']?.toString().trim() ?? '';
    if (id.isEmpty) throw const FormatException('message id missing');
    final payload = _safeMap(msg['payload']);
    final createdAtStr = (msg['createdAt'] ?? msg['created_at'])?.toString();
    final created = createdAtStr == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.tryParse(createdAtStr)?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0);
    final text = _renderPayloadText(payload);
    final mediaUrl = _extractMediaUrl(payload);
    final direction = _normalizeDirection(msg['direction']);
    final tags = _safeMap(msg['tags']);
    final replyTo = tags['whatsapp:replyTo']?.toString();
    final payloadType = payload['type']?.toString();
    final presentation = ConversationPresentationV1.fromPayload(
      payload,
      fallbackText: text,
      fallbackMediaUrl: mediaUrl,
    );

    return {
      'id': id,
      'message': text,
      'dateSent': created,
      'direction': direction,
      'isWhatsApp': true,
      'isSMS': false,
      'isAI': direction == 'outbound',
      'mediaUrl': mediaUrl,
      'bpTags': tags,
      'replyTo': replyTo,
      'payloadType': payloadType,
      'payload': payload,
      'presentationModel': presentation,
    };
  }

  Map<String, dynamic> _safeMap(dynamic value) {
    if (value is! Map) return const <String, dynamic>{};
    return value.map<String, dynamic>(
      (key, nested) => MapEntry(key.toString(), nested),
    );
  }

  Future<void> _recordFailure(
    String code,
    String stage, {
    StackTrace? stack,
    int skippedMessageCount = 0,
    String retryOutcome = 'not_attempted',
  }) {
    return CrashService.instance.recordNonFatal(
      code,
      stack,
      reason: 'botpress conversation recovery',
      context: {
        'diagnostic_surface': 'botpress_conversation',
        'diagnostic_code': code,
        'diagnostic_stage': stage,
        'diagnostic_retry_outcome': retryOutcome,
        'botpress_skipped_count': skippedMessageCount,
      },
    );
  }

  Future<void> _recordRetry(String retryOutcome) {
    return CrashService.instance.log(
      'botpress conversation credential retry',
      context: {
        'diagnostic_surface': 'botpress_conversation',
        'diagnostic_stage': 'credentials',
        'diagnostic_code': 'BOTPRESS_CREDENTIAL_RETRY',
        'diagnostic_retry_outcome': retryOutcome,
      },
    );
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
        final options = _safeList(payload['options']);
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
        final items = _safeList(payload['items']);
        return items
            .whereType<Map>()
            .map((c) => _renderCard(_safeMap(c)))
            .where((s) => s.isNotEmpty)
            .join('\n\n');
      case 'bloc':
        final items = _safeList(payload['items']);
        return items
            .whereType<Map>()
            .map((it) => _renderPayloadText(_safeMap(it)))
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
        return _safeText(payload['title']);
      case 'audio':
        return '🎵 Audio message';
      case 'video':
        return '🎬 Video message';
      case 'file':
        final title = _safeText(payload['title']);
        return title.isNotEmpty ? '📎 $title' : '📎 File';
    }

    return '';
  }

  String _renderCard(Map<String, dynamic> card) {
    final title = _safeText(card['title']);
    final subtitle = _safeText(card['subtitle']);
    final actions = _safeList(card['actions']);
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
      final items = _safeList(payload['items']);
      for (final it in items) {
        if (it is Map) {
          final found = _extractMediaUrl(_safeMap(it));
          if (found != null && found.isNotEmpty) return found;
        }
      }
    }
    return null;
  }

  List<dynamic> _safeList(dynamic value) =>
      value is List ? value : const <dynamic>[];

  String _safeText(dynamic value) {
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString();
    return '';
  }

  Future<_BotpressEnvelope> _fetchMessages(String customerId) async {
    final SecureFunctionResult request;
    try {
      request = await _client.postWithDiagnostics(
        _endpoint,
        {
          'customerId': customerId,
        },
      );
    } on SecureFunctionClientException catch (error) {
      final isAppCheck = error.code.startsWith('app-check');
      throw BotpressConversationException(
        isAppCheck
            ? 'BOTPRESS_APP_CHECK_UNAVAILABLE'
            : 'BOTPRESS_AUTHENTICATION_UNAVAILABLE',
        isAppCheck
            ? 'This app could not be verified to load bot history. Retry or reopen the app.'
            : 'Sign in again to load bot conversation history.',
        stage: 'credentials',
        retryOutcome: error.retryOutcome,
      );
    } catch (_) {
      throw const BotpressConversationException(
        'BOTPRESS_TRANSPORT_UNAVAILABLE',
        'Bot conversation history is temporarily unavailable. Retry to load it again.',
        stage: 'transport',
      );
    }
    final response = request.response;
    if (response.statusCode != 200) {
      Map<String, dynamic> body = const {};
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      final diagnostic = body['diagnostic'] is Map
          ? Map<String, dynamic>.from(body['diagnostic'] as Map)
          : const <String, dynamic>{};
      final responseCode = body['code']?.toString() ??
          diagnostic['code']?.toString() ??
          'BOTPRESS_PROXY_UNAVAILABLE';
      final isAppCheckFailure = responseCode.startsWith('APP_CHECK');
      final isAuthenticationFailure =
          responseCode.startsWith('AUTHENTICATION') ||
              (response.statusCode == 401 && !isAppCheckFailure);
      final isAuthorizationFailure = responseCode == 'ACCESS_DENIED' ||
          responseCode == 'CUSTOMER_ACCESS_DENIED';
      throw BotpressConversationException(
        responseCode,
        isAppCheckFailure
            ? 'This app could not be verified to load bot history. Retry or reopen the app.'
            : isAuthenticationFailure
                ? 'Sign in again to load bot conversation history.'
                : isAuthorizationFailure
                    ? 'Bot conversation history is unavailable for this customer.'
                    : 'Bot conversation history is temporarily unavailable. Retry to load it again.',
        stage: isAppCheckFailure ||
                isAuthenticationFailure ||
                isAuthorizationFailure
            ? 'credentials'
            : 'transport',
        retryOutcome: request.retryOutcome,
      );
    }
    late final Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      body = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw BotpressConversationException(
        'BOTPRESS_RESPONSE_INVALID',
        'Bot conversation history could not be read. Retry to load it again.',
        stage: 'response',
        retryOutcome: request.retryOutcome,
      );
    }
    if (body['state'] == 'not_found') {
      return _BotpressEnvelope(
        messages: const [],
        notFound: true,
        retryOutcome: request.retryOutcome,
      );
    }
    final messages = body['messages'];
    if (messages is! List) {
      throw BotpressConversationException(
        'BOTPRESS_RESPONSE_INVALID',
        'Bot conversation history could not be read. Retry to load it again.',
        stage: 'response',
        retryOutcome: request.retryOutcome,
      );
    }
    final diagnostic = _safeMap(body['diagnostic']);
    return _BotpressEnvelope(
      messages: messages,
      serverSkippedMessageCount:
          (diagnostic['skippedMessageCount'] as num?)?.toInt() ?? 0,
      retryOutcome: request.retryOutcome,
    );
  }

  String _normalizeDirection(dynamic d) {
    final v = d?.toString().toLowerCase();
    if (v == 'incoming') return 'inbound';
    if (v == 'outgoing') return 'outbound';
    return v ?? '';
  }
}
