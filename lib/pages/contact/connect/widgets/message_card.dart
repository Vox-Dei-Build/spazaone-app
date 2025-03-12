import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';

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
    var iconSize = SizeConfig.textMultiplier * 2;

    switch (statusText) {
      case "failed":
      case "undelivered":
        statusIcon = Icon(Icons.error,
            color: Colors.red, size: iconSize); // ❌ Failed/Undelivered
        break;
      case "sent":
        statusIcon = Icon(Icons.check,
            color: WaBrandColour.time, size: iconSize); // ✔️ Sent
        break;
      case "delivered":
        statusIcon = Icon(Icons.done_all,
            color: WaBrandColour.time, size: iconSize); // ✔✔ Delivered
        break;
      case "read": // ✅ Only for WhatsApp
        statusIcon = Icon(Icons.done_all,
            color: WaBrandColour.checkmarkBlue,
            size: iconSize); // ✔✔ Read (Only WhatsApp)
        break;
      default:
        statusIcon = Icon(Icons.done_all,
            color: WaBrandColour.checkmarkBlue, size: iconSize); // ⏳ Unknown
    }

    return Row(
      mainAxisAlignment:
          isMerchantMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        // ✅ Message Card
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
                  Row(
                    children: [
                      Text(
                        isWhatsApp ? "WhatsApp" : "SMS",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: SizeConfig.textMultiplier * 1.5,
                          color: Colors.black,
                        ),
                      ),

                      // AI indicator
                      if (message['isAI'] == true) ...[
                        SizedBox(width: SizeConfig.heightMultiplier * 0.4),
                        Text(
                          "AI Agent",
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
                  Text(
                    message['message'],
                    style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 2,
                        color: Colors.black),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ✅ Timestamp
                      Text(
                        DateFormat('HH:mm').format(message['dateSent']),
                        style: TextStyle(
                            fontSize: SizeConfig.textMultiplier * 1.5,
                            color: WaBrandColour.time),
                      ),
                      SizedBox(width: SizeConfig.heightMultiplier * 0.8),
                      // ✅ WhatsApp-style status icon
                      Align(
                        alignment: Alignment.center,
                        child: statusIcon,
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
}
