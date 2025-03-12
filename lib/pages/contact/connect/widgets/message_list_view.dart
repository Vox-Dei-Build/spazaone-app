import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:sticky_headers/sticky_headers.dart';
import 'message_card.dart';

class MessagesListView extends StatefulWidget {
  final List<Map<String, dynamic>> messages;
  final String? profileImageUrl;
  final String customerName;

  const MessagesListView({
    super.key,
    required this.messages,
    this.profileImageUrl,
    required this.customerName,
  });

  @override
  State<MessagesListView> createState() => _MessagesListViewState();
}

class _MessagesListViewState extends State<MessagesListView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => scrollToBottom());
  }

  void scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupMessagesByDate() {
    Map<String, List<Map<String, dynamic>>> groupedMessages = {};
    for (var message in widget.messages) {
      final dateKey = DateFormat('yyyy-MM-dd').format(message['dateSent']);
      groupedMessages.putIfAbsent(dateKey, () => []).add(message);
    }
    return groupedMessages;
  }

  String _formatDate(String date) {
    final messageDate = DateTime.parse(date);
    final today = DateTime.now();
    if (DateUtils.isSameDay(messageDate, today)) return "Today";
    if (DateUtils.isSameDay(
        messageDate, today.subtract(const Duration(days: 1)))) {
      return "Yesterday";
    }
    return DateFormat('dd MMM yyyy').format(messageDate);
  }

  @override
  Widget build(BuildContext context) {
    final groupedMessages = _groupMessagesByDate();
    final sortedDates = groupedMessages.keys.toList()
      ..sort((a, b) => a.compareTo(
          b)); // Oldest at top, newest at bottom (WhatsApp-style clearly!)

    return ListView.builder(
      controller: _scrollController,
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final messages = groupedMessages[date]!;

        return StickyHeader(
          header: _buildDateHeader(_formatDate(date)),
          content: Column(
            children: messages
                .map((msg) => MessageCard(
                      msg,
                      profileImageUrl: widget.profileImageUrl,
                      customerName: widget.customerName,
                    ))
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildDateHeader(String date) {
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        decoration: BoxDecoration(
          color: WaBrandColour.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          date,
          style: const TextStyle(fontSize: 12, color: WaBrandColour.time),
        ),
      ),
    );
  }
}
