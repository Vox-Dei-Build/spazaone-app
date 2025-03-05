import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'message_card.dart'; // Import the new MessageCard

class MessagesListView extends StatelessWidget {
  final List<Map<String, dynamic>> messages;

  const MessagesListView({super.key, required this.messages});

  Map<String, List<Map<String, dynamic>>> groupMessagesByDate() {
    Map<String, List<Map<String, dynamic>>> groupedMessages = {};

    for (var message in messages) {
      String formattedDate = _formatDate(message['dateSent']);
      if (!groupedMessages.containsKey(formattedDate)) {
        groupedMessages[formattedDate] = [];
      }
      groupedMessages[formattedDate]!.add(message);
    }

    return groupedMessages;
  }

  String _formatDate(DateTime date) {
    DateTime now = DateTime.now();
    if (DateFormat('yyyyMMdd').format(date) ==
        DateFormat('yyyyMMdd').format(now)) {
      return 'Today';
    } else if (DateFormat('yyyyMMdd').format(date) ==
        DateFormat('yyyyMMdd').format(now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    } else {
      return DateFormat('dd MMM yyyy').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    var groupedMessages = groupMessagesByDate();

    return ListView.builder(
      itemCount: groupedMessages.keys.length,
      itemBuilder: (context, index) {
        String date = groupedMessages.keys.elementAt(index);
        return Column(
          children: [
            _buildDateHeader(date),
            ...groupedMessages[date]!
                .map((message) => MessageCard(message))
                .toList(),
          ],
        );
      },
    );
  }

  Widget _buildDateHeader(String date) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 1,
      ),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 1.5,
            vertical: SizeConfig.heightMultiplier * 0.5,
          ),
          decoration: BoxDecoration(
            color: const Color(0xffbdbdbd),
            borderRadius:
                BorderRadius.circular(SizeConfig.heightMultiplier * 1),
          ),
          child: Text(
            date,
            style: TextStyle(
              fontWeight: FontWeight.w300,
              color: Colors.white,
              fontSize: SizeConfig.textMultiplier * 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
