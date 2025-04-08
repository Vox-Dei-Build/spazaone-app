import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/config/size_config.dart';

class NotificationTile extends StatelessWidget {
  final String message;
  final String templateType;
  final num messageCost;
  final String phone;
  final DateTime date;

  const NotificationTile({
    super.key,
    required this.message,
    required this.templateType,
    required this.messageCost,
    required this.phone,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        templateType == "whatsapp" ? FontAwesomeIcons.whatsapp : Icons.sms,
        color: templateType == "whatsapp" ? Colors.green : Colors.blue,
        size: SizeConfig.textMultiplier * 2,
      ),
      title: Text(
        "To: $phone",
        style: TextStyle(
          fontSize: SizeConfig.textMultiplier * 1.8,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        DateFormat.yMMMd().format(date),
        style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 1.5, color: Colors.grey),
      ),
      trailing: Text(
        "-${CurrencyUtil.format(messageCost.toDouble())}",
        style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: SizeConfig.textMultiplier * 1.5),
      ),
      onTap: () => _showMessageDetails(context),
    );
  }

  /// Opens a modal bottom sheet to show full message details
  void _showMessageDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      isScrollControlled: true, // ✅ Allows full-screen height if needed
      builder: (context) {
        return Padding(
          padding: EdgeInsets.symmetric(
            vertical: SizeConfig.heightMultiplier * 2,
            horizontal: SizeConfig.imageSizeMultiplier * 4,
          ),
          child: SingleChildScrollView(
            // ✅ Prevents overflow
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: SizeConfig.imageSizeMultiplier * 15,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 2),
                Text(
                  "Message Details",
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Divider(),
                SizedBox(height: SizeConfig.heightMultiplier * 1.5),
                _buildDetailRow("Recipient:", phone),
                _buildDetailRow("Date Sent:", DateFormat.yMMMd().format(date)),
                _buildDetailRow("Message Cost:",
                    "-${CurrencyUtil.format(messageCost.toDouble())}"),
                SizedBox(height: SizeConfig.heightMultiplier * 2),
                Text(
                  "Message Content:",
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 1),
                Container(
                  padding: EdgeInsets.all(SizeConfig.heightMultiplier * 1.5),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          SizeConfig.screenHeight * 0.3, // ✅ Limits text height
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        message,
                        style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 1.5,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 3),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Close"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Helper function for creating key-value rows in the modal
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding:
          EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 0.8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.5,
                color: Colors.grey[700],
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
