import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';

class MessageCard extends StatelessWidget {
  final Map<String, dynamic> message;
  final String? profileImageUrl;
  final String customerName;

  const MessageCard(this.message,
      {super.key, this.profileImageUrl, required this.customerName});

  @override
  Widget build(BuildContext context) {
    bool isMerchantMessage = message['direction'] == "outbound" ||
        message['direction'] == "outbound-api";
    bool isWhatsApp = message['isWhatsApp'] ?? false;

    // ✅ Determine WhatsApp/SMS status icon
    Icon statusIcon;
    String statusText = message['status'] ?? 'unknown';

    switch (statusText) {
      case "failed":
      case "undelivered":
        statusIcon = const Icon(Icons.error,
            color: Colors.red, size: 16); // ❌ Failed/Undelivered
        break;
      case "sent":
        statusIcon =
            const Icon(Icons.check, color: Colors.white, size: 16); // ✔️ Sent
        break;
      case "delivered":
        statusIcon = const Icon(Icons.done_all,
            color: Colors.white, size: 16); // ✔✔ Delivered
        break;
      case "read": // ✅ Only for WhatsApp
        statusIcon = const Icon(Icons.done_all,
            color: Colors.lightBlueAccent, size: 16); // ✔✔ Read (Only WhatsApp)
        break;
      default:
        statusIcon = const Icon(Icons.done_all,
            color: Colors.lightBlueAccent, size: 16); // ⏳ Unknown
    }

    return Row(
      mainAxisAlignment:
          isMerchantMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        // ✅ Show Avatar ONLY for customer messages
        if (!isMerchantMessage)
          Padding(
            padding:
                EdgeInsets.only(right: SizeConfig.imageSizeMultiplier * 1.5),
            child: _buildAvatar(),
          ),

        // ✅ Message Card
        Container(
          width: SizeConfig.screenWidth *
              (SizeConfig.screenWidth > 360 ? 0.7 : 0.9),
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
            color: isMerchantMessage ? Colors.green : Colors.white,
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: SizeConfig.heightMultiplier * 1.5,
                horizontal: SizeConfig.imageSizeMultiplier * 3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isWhatsApp ? "WhatsApp" : "SMS",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: SizeConfig.textMultiplier * 1.5,
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 1),
                  Text(
                    message['message'],
                    style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 2,
                        color: isMerchantMessage ? Colors.white : Colors.black),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ✅ WhatsApp-style status icon
                      statusIcon,

                      // ✅ Timestamp
                      Text(
                        isMerchantMessage
                            ? "Sent at ${DateFormat('HH:mm').format(message['dateSent'])}"
                            : "Received at ${DateFormat('HH:mm').format(message['dateSent'])}",
                        style: TextStyle(
                            fontSize: SizeConfig.textMultiplier * 1.5,
                            color: isMerchantMessage
                                ? Colors.white
                                : Colors.black),
                      ),
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

  // ✅ Avatar Builder: Uses Profile Image or Initial
  Widget _buildAvatar() {
    return CircleAvatar(
      radius: SizeConfig.heightMultiplier * 2.5,
      backgroundImage: profileImageUrl != null
          ? CachedNetworkImageProvider(profileImageUrl!)
          : null,
      backgroundColor: profileImageUrl == null ? Colors.blueGrey : null,
      child: profileImageUrl == null
          ? Text(
              customerName.isNotEmpty ? customerName[0].toUpperCase() : '?',
              style: TextStyle(
                color: Colors.white,
                fontSize: SizeConfig.textMultiplier * 2,
                fontWeight: FontWeight.w500,
              ),
            )
          : null,
    );
  }
}
