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
    final bool isMerchantMessage =
        (message['direction']?.toString().toLowerCase() == 'outbound') ||
            (message['direction']?.toString().toLowerCase() == 'outbound-api');
    final bool isWhatsApp = (message['isWhatsApp'] as bool?) ?? false;
    final String? mediaUrl = message['mediaUrl'] as String?;
    final DateTime dateSent = message['dateSent'] is DateTime
        ? (message['dateSent'] as DateTime)
        : DateTime.parse(message['dateSent'].toString());

    // ✅ Status block (yours + read heuristic)
    String statusText;
    if (message['direction']?.toString().toLowerCase() == 'inbound' ||
        message['isRead'] == true) {
      statusText = 'read';
    } else {
      statusText = (message['status'] ?? 'unknown').toString().toLowerCase();
    }

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
                  // 1️⃣ Media (tap → ImageViewerPage)
                  if (mediaUrl != null && mediaUrl.trim().isNotEmpty) ...[
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ImageViewerPage(imageUrl: mediaUrl),
                          ),
                        );
                      },
                      child: Hero(
                        tag: mediaUrl,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            mediaUrl,
                            width: double.infinity,
                            height: 180,
                            fit: BoxFit.cover,
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
                  Builder(builder: (context) {
                    final body = (message['message'] as String?) ?? '';
                    if (body.trim().isNotEmpty) {
                      return Text(
                        body,
                        style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 2,
                          color: Colors.black,
                        ),
                      );
                    }
                    // PAS-AI-02: avoid blank bubbles. If we have media we
                    // already rendered it above; otherwise surface the
                    // payload type so merchants still see *something* and
                    // know an AI/Botpress message exists.
                    final hasMedia =
                        mediaUrl != null && mediaUrl.trim().isNotEmpty;
                    if (hasMedia) return const SizedBox.shrink();
                    final payloadType =
                        (message['payloadType'] as String?)?.trim();
                    final fallback = (payloadType == null ||
                            payloadType.isEmpty)
                        ? 'Message'
                        : '[${payloadType[0].toUpperCase()}${payloadType.substring(1)} message]';
                    return Text(
                      fallback,
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.8,
                        color: Colors.black54,
                        fontStyle: FontStyle.italic,
                      ),
                    );
                  }),

                  SizedBox(height: SizeConfig.heightMultiplier * 2),

                  // 4️⃣ Time & status icon
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(dateSent.toLocal()),
                        style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 1.5,
                          color: WaBrandColour.time,
                        ),
                      ),
                      SizedBox(width: SizeConfig.heightMultiplier * 0.8),
                      if (isMerchantMessage) statusIcon,
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
