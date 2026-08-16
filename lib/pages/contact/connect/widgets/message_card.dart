import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/conversation/conversation_presentation.dart';
import 'package:url_launcher/url_launcher.dart';

final DateFormat _messageTimeFormat = DateFormat('HH:mm');
final RegExp _whatsAppTokenPattern = RegExp(
  r'(```[\s\S]+?```|\*[^*\n]+\*|_[^_\n]+_|~[^~\n]+~|https?://[^\s]+)',
);

class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(
            imageUrl,
            errorBuilder: (_, __, ___) => const _ExpiredMedia(
              label: 'This image is no longer available.',
              dark: true,
            ),
          ),
        ),
      ),
    );
  }
}

class MessageCard extends StatelessWidget {
  const MessageCard(
    this.message, {
    super.key,
    this.profileImageUrl,
    required this.customerName,
  });

  final Map<String, dynamic> message;
  final String? profileImageUrl;
  final String customerName;

  @override
  Widget build(BuildContext context) {
    final direction = message['direction']?.toString().toLowerCase();
    final isMerchant = direction == 'outbound' || direction == 'outbound-api';
    final isWhatsApp = message['isWhatsApp'] == true;
    final dateSent = message['dateSent'] is DateTime
        ? message['dateSent'] as DateTime
        : DateTime.tryParse(message['dateSent']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
    final presentation = ConversationPresentationV1.fromMessage(message);

    return Align(
      alignment: isMerchant ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .84,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: isMerchant ? WaBrandColour.outgoingChatBubble : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: isMerchant ? const Radius.circular(14) : Radius.zero,
            bottomRight: isMerchant ? Radius.zero : const Radius.circular(14),
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x18000000), blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message['quotedText'] case final String quotedText) ...[
                _QuotedReply(
                  text: quotedText,
                  isMerchant:
                      message['quotedDirection']?.toString().toLowerCase() ==
                          'outbound',
                ),
                const SizedBox(height: 7),
              ],
              _PresentationBody(presentation: presentation),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isWhatsApp)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 11,
                        color: WaBrandColour.time,
                        semanticLabel: message['isAI'] == true
                            ? 'WhatsApp automated reply'
                            : 'WhatsApp',
                      ),
                    ),
                  Text(
                    _messageTimeFormat.format(dateSent.toLocal()),
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.35,
                      color: WaBrandColour.time,
                    ),
                  ),
                  if (isMerchant) ...[
                    const SizedBox(width: 4),
                    _MessageStatusIcon(message: message),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuotedReply extends StatelessWidget {
  const _QuotedReply({required this.text, required this.isMerchant});

  final String text;
  final bool isMerchant;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .055),
        border: Border(
          left: BorderSide(
            width: 3,
            color: isMerchant ? Colors.green.shade700 : Colors.blue.shade700,
          ),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _PresentationBody extends StatelessWidget {
  const _PresentationBody({required this.presentation});

  final ConversationPresentationV1 presentation;

  @override
  Widget build(BuildContext context) {
    return switch (presentation.type) {
      ConversationPresentationType.text =>
        WhatsAppFormattedText(presentation.text ?? ''),
      ConversationPresentationType.image => _ImagePresentation(presentation),
      ConversationPresentationType.choices ||
      ConversationPresentationType.list =>
        _OptionsPresentation(presentation),
      ConversationPresentationType.carousel =>
        _CarouselPresentation(presentation),
      ConversationPresentationType.audio => _MediaTile(
          icon: Icons.mic_rounded,
          label: presentation.text ?? 'Voice message',
          url: presentation.mediaUrl,
        ),
      ConversationPresentationType.video => _MediaTile(
          icon: Icons.videocam_rounded,
          label: presentation.text ?? 'Video',
          url: presentation.mediaUrl,
        ),
      ConversationPresentationType.document => _MediaTile(
          icon: Icons.description_rounded,
          label: presentation.fileName ?? presentation.text ?? 'Document',
          url: presentation.mediaUrl,
        ),
      ConversationPresentationType.location => _LocationPresentation(
          presentation,
        ),
      ConversationPresentationType.unsupported => Text(
          presentation.text ?? 'This message cannot be previewed.',
          style: const TextStyle(
              color: Colors.black54, fontStyle: FontStyle.italic),
        ),
    };
  }
}

class WhatsAppFormattedText extends StatelessWidget {
  const WhatsAppFormattedText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Colors.black87,
          height: 1.3,
        );
    return Text.rich(
      TextSpan(style: base, children: whatsappTextSpans(text, base)),
    );
  }
}

@visibleForTesting
List<InlineSpan> whatsappTextSpans(String input, TextStyle? base) {
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in _whatsAppTokenPattern.allMatches(input)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: input.substring(cursor, match.start)));
    }
    final token = match.group(0)!;
    if (token.startsWith('http')) {
      spans.add(
        TextSpan(
          text: token,
          style: base?.copyWith(
            color: Colors.blue.shade800,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => launchUrl(
                  Uri.parse(token),
                  mode: LaunchMode.externalApplication,
                ),
        ),
      );
    } else if (token.startsWith('```')) {
      spans.add(
        TextSpan(
          text: token.substring(3, token.length - 3),
          style: base?.copyWith(
            fontFamily: 'monospace',
            backgroundColor: Colors.black.withValues(alpha: .07),
          ),
        ),
      );
    } else {
      final marker = token[0];
      spans.add(
        TextSpan(
          text: token.substring(1, token.length - 1),
          style: base?.copyWith(
            fontWeight: marker == '*' ? FontWeight.w700 : null,
            fontStyle: marker == '_' ? FontStyle.italic : null,
            decoration: marker == '~' ? TextDecoration.lineThrough : null,
          ),
        ),
      );
    }
    cursor = match.end;
  }
  if (cursor < input.length) spans.add(TextSpan(text: input.substring(cursor)));
  return spans;
}

class _ImagePresentation extends StatelessWidget {
  const _ImagePresentation(this.presentation);

  final ConversationPresentationV1 presentation;

  @override
  Widget build(BuildContext context) {
    final url = presentation.mediaUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url == null)
          const _ExpiredMedia(label: 'This image is no longer available.')
        else
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ImageViewerPage(imageUrl: url)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Image.network(
                  url,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const SizedBox(
                          height: 160,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                  errorBuilder: (_, __, ___) => const _ExpiredMedia(
                    label: 'This image is no longer available.',
                  ),
                ),
              ),
            ),
          ),
        if (presentation.text case final caption?) ...[
          const SizedBox(height: 8),
          WhatsAppFormattedText(caption),
        ],
      ],
    );
  }
}

class _OptionsPresentation extends StatelessWidget {
  const _OptionsPresentation(this.presentation);

  final ConversationPresentationV1 presentation;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (presentation.title case final title?) ...[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
        ],
        if (presentation.text case final text?) WhatsAppFormattedText(text),
        if (presentation.options.isNotEmpty) const Divider(height: 18),
        for (final option in presentation.options)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x17000000))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.label,
                  style: TextStyle(
                    color: Colors.blue.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (option.description case final description?)
                  Text(description,
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        if (presentation.footer case final footer?) ...[
          const SizedBox(height: 7),
          Text(footer, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _CarouselPresentation extends StatelessWidget {
  const _CarouselPresentation(this.presentation);

  final ConversationPresentationV1 presentation;

  @override
  Widget build(BuildContext context) {
    if (presentation.cards.isEmpty) {
      return WhatsAppFormattedText(presentation.text ?? 'Product cards');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (presentation.text case final text?) ...[
          WhatsAppFormattedText(text),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: 250,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: presentation.cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, index) => _TranscriptCard(
              card: presentation.cards[index],
            ),
          ),
        ),
      ],
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({required this.card});

  final ConversationCardPresentation card;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (card.imageUrl case final url?)
            Image.network(
              url,
              height: 105,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 105,
                child: _ExpiredMedia(label: 'Image unavailable'),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (card.subtitle case final subtitle?) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const Spacer(),
                  for (final action in card.actions.take(2))
                    Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.icon, required this.label, this.url});

  final IconData icon;
  final String label;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: url == null
          ? null
          : () =>
              launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
      child: Row(
        children: [
          CircleAvatar(child: Icon(icon)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Icon(url == null ? Icons.error_outline : Icons.open_in_new, size: 18),
        ],
      ),
    );
  }
}

class _LocationPresentation extends StatelessWidget {
  const _LocationPresentation(this.presentation);

  final ConversationPresentationV1 presentation;

  @override
  Widget build(BuildContext context) {
    final lat = presentation.latitude;
    final lon = presentation.longitude;
    final uri = lat == null || lon == null
        ? null
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    return _MediaTile(
      icon: Icons.location_on_rounded,
      label: presentation.text ?? presentation.title ?? 'Location',
      url: uri?.toString(),
    );
  }
}

class _ExpiredMedia extends StatelessWidget {
  const _ExpiredMedia({required this.label, this.dark = false});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      color: dark ? Colors.black : Colors.grey.shade200,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(color: dark ? Colors.white70 : Colors.black54),
      ),
    );
  }
}

class _MessageStatusIcon extends StatelessWidget {
  const _MessageStatusIcon({required this.message});

  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final status = message['isRead'] == true
        ? 'read'
        : (message['status'] ?? 'unknown').toString().toLowerCase();
    return switch (status) {
      'failed' ||
      'undelivered' =>
        const Icon(Icons.error, color: Colors.red, size: 14),
      'sent' => const Icon(Icons.check, color: WaBrandColour.time, size: 14),
      'delivered' =>
        const Icon(Icons.done_all, color: WaBrandColour.time, size: 14),
      'read' => const Icon(Icons.done_all,
          color: WaBrandColour.checkmarkBlue, size: 14),
      _ => const Icon(Icons.access_time, color: WaBrandColour.time, size: 14),
    };
  }
}
