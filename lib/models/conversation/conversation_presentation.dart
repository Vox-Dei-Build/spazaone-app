class ConversationOption {
  const ConversationOption({required this.label, this.description});

  final String label;
  final String? description;
}

class ConversationCardPresentation {
  const ConversationCardPresentation({
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.actions = const <ConversationOption>[],
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final List<ConversationOption> actions;
}

enum ConversationPresentationType {
  text,
  image,
  choices,
  list,
  carousel,
  audio,
  video,
  document,
  location,
  unsupported,
}

/// Safe, display-only representation of a WhatsApp/Botpress message.
///
/// Values used to execute provider actions are intentionally discarded. The
/// customer transcript may show what was offered but can never replay it.
class ConversationPresentationV1 {
  const ConversationPresentationV1({
    required this.type,
    this.text,
    this.title,
    this.footer,
    this.mediaUrl,
    this.fileName,
    this.latitude,
    this.longitude,
    this.replyToId,
    this.options = const <ConversationOption>[],
    this.cards = const <ConversationCardPresentation>[],
  });

  final ConversationPresentationType type;
  final String? text;
  final String? title;
  final String? footer;
  final String? mediaUrl;
  final String? fileName;
  final double? latitude;
  final double? longitude;
  final String? replyToId;
  final List<ConversationOption> options;
  final List<ConversationCardPresentation> cards;

  int get richnessScore {
    var score = switch (type) {
      ConversationPresentationType.text => 10,
      ConversationPresentationType.unsupported => 1,
      _ => 30,
    };
    score += options.length * 2 + cards.length * 4;
    if (mediaUrl != null) score += 5;
    return score;
  }

  static ConversationPresentationV1 fromMessage(Map<String, dynamic> message) {
    final normalized = message['presentationModel'];
    if (normalized is ConversationPresentationV1) return normalized;
    final stored = _map(message['presentation']);
    if (stored != null &&
        (stored['schemaVersion'] == 1 || stored['version'] == 1)) {
      return fromPayload(
        stored,
        fallbackText: message['message']?.toString(),
        fallbackMediaUrl: message['mediaUrl']?.toString(),
      );
    }
    return fromPayload(
      _map(message['payload']) ?? const <String, dynamic>{},
      fallbackText: message['message']?.toString(),
      fallbackMediaUrl: message['mediaUrl']?.toString(),
    );
  }

  static ConversationPresentationV1 fromPayload(
    Map<String, dynamic> payload, {
    String? fallbackText,
    String? fallbackMediaUrl,
  }) {
    final rawType =
        (payload['type'] ?? payload['kind'])?.toString().toLowerCase();
    final text = _firstText([
      payload['text'],
      payload['markdown'],
      payload['caption'],
      fallbackText,
    ]);
    final mediaUrl = _safeUrl(_firstText([
      payload['imageUrl'],
      payload['audioUrl'],
      payload['videoUrl'],
      payload['fileUrl'],
      payload['mediaUrl'],
      fallbackMediaUrl,
    ]));
    final replyToId = _safeReference(
      _firstText([payload['replyToId'], payload['replyTo']]),
    );

    if (rawType == 'bloc') {
      final items = _maps(payload['items']);
      final rich = items
          .map((item) => fromPayload(item, fallbackText: text))
          .where((item) => item.type != ConversationPresentationType.text)
          .toList();
      if (rich.isNotEmpty) return rich.first;
    }

    if (rawType == 'choice' || rawType == 'choices' || rawType == 'buttons') {
      return ConversationPresentationV1(
        type: ConversationPresentationType.choices,
        text: text,
        options: _options(payload['options'] ?? payload['buttons']),
        replyToId: replyToId,
      );
    }
    if (rawType == 'dropdown' || rawType == 'list') {
      final sectionOptions = <ConversationOption>[];
      for (final section in _maps(payload['sections'])) {
        final sectionTitle = _firstText([section['title']]);
        for (final option in _options(section['rows'] ?? section['options'])) {
          sectionOptions.add(
            ConversationOption(
              label: option.label,
              description: _joinNonEmpty(sectionTitle, option.description),
            ),
          );
        }
      }
      return ConversationPresentationV1(
        type: ConversationPresentationType.list,
        title: _firstText([payload['title'], payload['header']]),
        text: text,
        footer: _firstText([payload['footer'], payload['buttonLabel']]),
        options: sectionOptions.isNotEmpty
            ? List.unmodifiable(sectionOptions.take(40))
            : _options(payload['options']),
        replyToId: replyToId,
      );
    }
    if (rawType == 'card') {
      return ConversationPresentationV1(
        type: ConversationPresentationType.carousel,
        text: text,
        cards: <ConversationCardPresentation>[_card(payload)],
        replyToId: replyToId,
      );
    }
    if (rawType == 'carousel') {
      final values = payload['cards'] ?? payload['items'];
      return ConversationPresentationV1(
        type: ConversationPresentationType.carousel,
        text: text,
        cards: _maps(values).take(20).map(_card).toList(growable: false),
        replyToId: replyToId,
      );
    }
    if (rawType == 'image' ||
        (mediaUrl != null && rawType == null && _looksLikeImage(mediaUrl))) {
      return ConversationPresentationV1(
        type: ConversationPresentationType.image,
        text: text,
        mediaUrl: mediaUrl,
        replyToId: replyToId,
      );
    }
    if (rawType == 'audio') {
      return ConversationPresentationV1(
        type: ConversationPresentationType.audio,
        text: text,
        mediaUrl: mediaUrl,
        replyToId: replyToId,
      );
    }
    if (rawType == 'video') {
      return ConversationPresentationV1(
        type: ConversationPresentationType.video,
        text: text,
        mediaUrl: mediaUrl,
        replyToId: replyToId,
      );
    }
    if (rawType == 'file' || rawType == 'document') {
      return ConversationPresentationV1(
        type: ConversationPresentationType.document,
        text: text,
        mediaUrl: mediaUrl,
        fileName: _firstText([payload['fileName'], payload['title']]),
        replyToId: replyToId,
      );
    }
    if (rawType == 'location') {
      return ConversationPresentationV1(
        type: ConversationPresentationType.location,
        title: _firstText([payload['title']]),
        text: _firstText([payload['address'], text]),
        latitude: _number(payload['latitude']),
        longitude: _number(payload['longitude']),
        replyToId: replyToId,
      );
    }
    if (text != null || mediaUrl != null) {
      return ConversationPresentationV1(
        type: mediaUrl != null
            ? ConversationPresentationType.image
            : ConversationPresentationType.text,
        text: text,
        mediaUrl: mediaUrl,
        replyToId: replyToId,
      );
    }
    return const ConversationPresentationV1(
      type: ConversationPresentationType.unsupported,
      text: 'This message cannot be previewed.',
    );
  }

  static ConversationCardPresentation _card(Map<String, dynamic> value) {
    return ConversationCardPresentation(
      title: _firstText([value['title']]) ?? 'Item',
      subtitle: _firstText([value['subtitle'], value['description']]),
      imageUrl: _safeUrl(_firstText([value['imageUrl'], value['image']])),
      actions: _options(value['actions'] ?? value['buttons']),
    );
  }

  static List<ConversationOption> _options(dynamic value) => _maps(value)
      .map(
        (option) => ConversationOption(
          label: _firstText([
                option['label'],
                option['title'],
                option['text'],
              ]) ??
              'Option',
          description: _firstText([option['description']]),
        ),
      )
      .take(40)
      .toList(growable: false);

  static Map<String, dynamic>? _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static Iterable<Map<String, dynamic>> _maps(dynamic value) sync* {
    if (value is! List) return;
    for (final item in value) {
      final map = _map(item);
      if (map != null) yield map;
    }
  }

  static String? _firstText(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static String? _safeUrl(String? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
        ? uri.toString()
        : null;
  }

  static String? _safeReference(String? value) =>
      value != null && RegExp(r'^[A-Za-z0-9:_-]{1,256}$').hasMatch(value)
          ? value
          : null;

  static double? _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static bool _looksLikeImage(String value) =>
      RegExp(r'\.(?:png|jpe?g|webp|gif)(?:\?|$)', caseSensitive: false)
          .hasMatch(value);

  static String? _joinNonEmpty(String? left, String? right) {
    if (left == null) return right;
    if (right == null) return left;
    return '$left · $right';
  }
}
