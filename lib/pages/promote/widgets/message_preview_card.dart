import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';

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
      elevation: compact ? 0 : 2,
      margin: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
      color: compact ? Theme.of(context).colorScheme.surface : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 16 : 12),
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
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(compact ? 16 : 12),
                  topRight: Radius.circular(compact ? 16 : 12),
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
            padding: compact
                ? const EdgeInsets.all(14)
                : LayoutConstants.padding10Horizontal,
            child: Text(
              content,
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * (compact ? 1.65 : 1.8),
                height: compact ? 1.35 : 1.5,
              ),
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
