import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';

class MessagePreviewCard extends StatelessWidget {
  final String content;
  final String? mediaUrl;

  const MessagePreviewCard({
    Key? key,
    required this.content,
    this.mediaUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mediaUrl != null && mediaUrl!.isNotEmpty)
            GestureDetector(
              onTap: () => _openImagePreview(context, mediaUrl!),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                child: Image.network(
                  mediaUrl!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image, size: 100),
                ),
              ),
            ),
          Padding(
            padding: LayoutConstants.padding10Horizontal,
            child: Text(
              content,
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.8,
                height: 1.5,
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
