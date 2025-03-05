import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'message_card.dart';

class MessagesListView extends StatefulWidget {
  final List<Map<String, dynamic>> messages;
  final String? profileImageUrl; // ✅ Add profile image URL
  final String customerName; // ✅ Add customer name for initials fallback
  const MessagesListView(
      {super.key,
      required this.messages,
      this.profileImageUrl,
      required this.customerName});

  @override
  _MessagesListViewState createState() => _MessagesListViewState();
}

class _MessagesListViewState extends State<MessagesListView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant MessagesListView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ Auto-scroll to the bottom when new messages arrive
    if (widget.messages.length > oldWidget.messages.length) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.minScrollExtent);
        }
      });
    }
  }

  Map<String, List<Map<String, dynamic>>> groupMessagesByDate() {
    Map<String, List<Map<String, dynamic>>> groupedMessages = {};

    for (var message in widget.messages) {
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
    var reversedKeys =
        groupedMessages.keys.toList().reversed.toList(); // ✅ Reverse order

    return ListView.builder(
      controller: _scrollController,
      reverse: true, // ✅ Newest messages at the bottom
      itemCount: reversedKeys.length,
      itemBuilder: (context, index) {
        String date = reversedKeys[index];
        return Column(
          children: [
            _buildDateHeader(date),
            ...groupedMessages[date]!
                .map((message) => MessageCard(
                      message,
                      profileImageUrl: widget.profileImageUrl,
                      customerName: widget.customerName,
                    ))
                .toList()
                .reversed, // ✅ Reverse messages per day
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
