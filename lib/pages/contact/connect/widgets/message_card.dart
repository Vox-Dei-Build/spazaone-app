import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';

/// Full‑screen image viewer with pinch/zoom support.
class ImageViewerPage extends StatelessWidget {
  final String imageUrl;
  const ImageViewerPage({
    Key? key,
    required this.imageUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // A simple "X" close button
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(imageUrl),
        ),
      ),
    );
  }
}

/// A chat bubble that displays text + optional media. Tapping the media opens [ImageViewerPage].
class MessageCard extends StatelessWidget {
  final Map<String, dynamic> message;
  final String? profileImageUrl;
  final String customerName;

  const MessageCard(
    this.message, {
    Key? key,
    this.profileImageUrl,
    required this.customerName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isMerchantMessage = message['direction'] == 'outbound' ||
        message['direction'] == 'outbound-api';
    final bool isWhatsApp = message['isWhatsApp'] ?? false;

    // Determine status icon
    final String statusText = message['status'] ?? 'unknown';
    final double iconSize = SizeConfig.textMultiplier * 2;
    Icon statusIcon;
    switch (statusText) {
      case 'failed':
      case 'undelivered':
        statusIcon = Icon(Icons.error, color: Colors.red, size: iconSize);
        break;
      case 'sent':
        statusIcon =
            Icon(Icons.check, color: WaBrandColour.time, size: iconSize);
        break;
      case 'delivered':
        statusIcon =
            Icon(Icons.done_all, color: WaBrandColour.time, size: iconSize);
        break;
      case 'read':
        statusIcon = Icon(
          Icons.done_all,
          color: WaBrandColour.checkmarkBlue,
          size: iconSize,
        );
        break;
      default:
        statusIcon =
            Icon(Icons.access_time, color: WaBrandColour.time, size: iconSize);
    }

    final String? mediaUrl = message['mediaUrl'] as String?;
    final DateTime dateSent = message['dateSent'] as DateTime;

    return Row(
      mainAxisAlignment:
          isMerchantMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Container(
          width:
              SizeConfig.screenWidth * (SizeConfig.screenWidth > 360 ? 0.8 : 1),
          margin: EdgeInsets.symmetric(
            vertical: SizeConfig.heightMultiplier * 0.5,
          ),
          child: Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft:
                    isMerchantMessage ? const Radius.circular(12) : Radius.zero,
                bottomRight:
                    isMerchantMessage ? Radius.zero : const Radius.circular(12),
              ),
            ),
            color: isMerchantMessage
                ? WaBrandColour.outgoingChatBubble
                : WaBrandColour.white,
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: SizeConfig.heightMultiplier * 1,
                horizontal: SizeConfig.imageSizeMultiplier * 2.5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1️⃣ IMAGE (if present & tappable)
                  if (mediaUrl != null && mediaUrl.trim().isNotEmpty) ...[
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ImageViewerPage(imageUrl: mediaUrl),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          mediaUrl,
                          width: double.infinity,
                          height: 180,
                          fit: BoxFit.cover,
                          loadingBuilder: (ctx, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              height: 180,
                              alignment: Alignment.center,
                              child: CircularProgressIndicator(
                                value: progress.expectedTotalBytes != null
                                    ? progress.cumulativeBytesLoaded /
                                        progress.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                          errorBuilder: (ctx, _, __) => Container(
                            height: 180,
                            color: Colors.grey[200],
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image, size: 48),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 1),
                  ],

                  // 2️⃣ Channel + AI tag
                  Row(
                    children: [
                      Text(
                        isWhatsApp ? 'WhatsApp' : 'SMS',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: SizeConfig.textMultiplier * 1.5,
                          color: Colors.black,
                        ),
                      ),
                      if (message['isAI'] == true) ...[
                        SizedBox(width: SizeConfig.heightMultiplier * 0.4),
                        Text(
                          'AI Agent',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: SizeConfig.textMultiplier * 1.5,
                            color: Colors.black,
                          ),
                        ),
                        SizedBox(width: SizeConfig.heightMultiplier * 0.5),
                        Icon(
                          Icons.verified_rounded,
                          color: WaBrandColour.lightGreen,
                          size: SizeConfig.imageSizeMultiplier * 4,
                        ),
                      ],
                    ],
                  ),

                  SizedBox(height: SizeConfig.heightMultiplier * 1),

                  // 3️⃣ Text body
                  Text(
                    message['message'] as String? ?? '',
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 2,
                      color: Colors.black,
                    ),
                  ),

                  SizedBox(height: SizeConfig.heightMultiplier * 2),

                  // 4️⃣ Timestamp & status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(dateSent),
                        style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 1.5,
                          color: WaBrandColour.time,
                        ),
                      ),
                      SizedBox(width: SizeConfig.heightMultiplier * 0.8),
                      statusIcon,
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
