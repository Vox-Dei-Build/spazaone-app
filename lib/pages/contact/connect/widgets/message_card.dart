import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';

class MessageCard extends StatelessWidget {
  final Map<String, dynamic> message;

  const MessageCard(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    bool isMerchantMessage = message['isMerchant'] ?? false;

    return Align(
      alignment:
          isMerchantMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width:
            SizeConfig.screenWidth * (SizeConfig.screenWidth > 360 ? 0.7 : 0.9),
        margin: EdgeInsets.symmetric(
          vertical: SizeConfig.heightMultiplier * 0.5,
          horizontal: SizeConfig.imageSizeMultiplier * 2,
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
          color: isMerchantMessage ? Colors.white : Colors.grey[500],
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: SizeConfig.heightMultiplier * 1.5,
              horizontal: SizeConfig.imageSizeMultiplier * 3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message['message'],
                  style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 2,
                      color: isMerchantMessage ? Colors.black87 : Colors.white),
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 2),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    "Sent at ${DateFormat('HH:mm').format(message['dateSent'])}",
                    style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.5,
                        color:
                            isMerchantMessage ? Colors.black87 : Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
