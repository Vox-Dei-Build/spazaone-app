import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

class MessagePreviewCard extends StatelessWidget {
  final String content;
  final String? mediaUrl;
  final bool compact;

  const MessagePreviewCard({
    Key? key,
    required this.content,
    this.mediaUrl,
    this.compact = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
      color: compact ? Theme.of(context).colorScheme.surface : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
        side: compact
            ? BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
              )
            : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mediaUrl != null && mediaUrl!.isNotEmpty)
            GestureDetector(
              onTap: () => _openImagePreview(context, mediaUrl!),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(SpazaRadius.surface),
                  topRight: Radius.circular(SpazaRadius.surface),
                ),
                child: Image.network(
                  mediaUrl!,
                  height: compact ? 112 : 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image, size: 100),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              content,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  void _openImagePreview(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.black,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(), // tap anywhere to close
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 3.0,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                  child:
                      Icon(Icons.broken_image, size: 100, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}
