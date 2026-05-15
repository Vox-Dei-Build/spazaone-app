import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
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
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _lastMessageCount = widget.messages.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Delay to ensure long lists + sticky headers finish layout
      Future.delayed(const Duration(milliseconds: 100), scrollToBottom);
    });
  }

  @override
  void didUpdateWidget(covariant MessagesListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != _lastMessageCount) {
      _lastMessageCount = widget.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 50), scrollToBottom);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void scrollToBottom({int retry = 0}) {
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      final maxExtent = position.maxScrollExtent;
      final currentOffset = position.pixels;

      // If not at the bottom, try again (with a small delay)
      if ((maxExtent - currentOffset).abs() > 50.0 && retry < 3) {
        Future.delayed(const Duration(milliseconds: 100), () {
          scrollToBottom(retry: retry + 1);
        });
      }

      _scrollController.animateTo(maxExtent,
          curve: Curves.easeOut, duration: const Duration(milliseconds: 100));
    }
  }

  List<_MessageRow> _buildRows() {
    final rows = <_MessageRow>[];
    String? currentDateKey;

    for (final message in widget.messages) {
      final date = _asDate(message['dateSent']);
      if (date == null) continue;

      final dateKey = DateFormat('yyyy-MM-dd').format(date);
      if (dateKey != currentDateKey) {
        rows.add(_MessageRow.header(dateKey));
        currentDateKey = dateKey;
      }
      rows.add(_MessageRow.message(message));
    }
    return rows;
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
    final rows = _buildRows();

    return ListView.builder(
      controller: _scrollController,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.dateKey != null) {
          return _buildDateHeader(_formatDate(row.dateKey!));
        }
        return MessageCard(
          row.message!,
          profileImageUrl: widget.profileImageUrl,
          customerName: widget.customerName,
        );
      },
    );
  }

  DateTime? _asDate(dynamic value) {
    if (value is DateTime) return value;
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
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

class _MessageRow {
  final String? dateKey;
  final Map<String, dynamic>? message;

  const _MessageRow._({this.dateKey, this.message});

  factory _MessageRow.header(String dateKey) => _MessageRow._(dateKey: dateKey);

  factory _MessageRow.message(Map<String, dynamic> message) =>
      _MessageRow._(message: message);
}
