import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/conversation/conversation_presentation.dart';
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
  int _scrollRequest = 0;
  String _latestMessageKey = '';

  @override
  void initState() {
    super.initState();
    _lastMessageCount = widget.messages.length;
    _latestMessageKey = _messageKey(widget.messages);
    _scheduleScrollToBottom();
  }

  @override
  void didUpdateWidget(covariant MessagesListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final latestMessageKey = _messageKey(widget.messages);
    if (widget.messages.length != _lastMessageCount ||
        latestMessageKey != _latestMessageKey) {
      _lastMessageCount = widget.messages.length;
      _latestMessageKey = latestMessageKey;
      _scheduleScrollToBottom();
    }
  }

  @override
  void dispose() {
    _scrollRequest++;
    _scrollController.dispose();
    super.dispose();
  }

  String _messageKey(List<Map<String, dynamic>> messages) {
    if (messages.isEmpty) return '';
    final latest = messages.last;
    return '${latest['sid'] ?? latest['id'] ?? ''}:'
        '${latest['dateSent'] ?? ''}:'
        '${latest['message'] ?? ''}';
  }

  void _scheduleScrollToBottom() {
    final request = ++_scrollRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToBottom(request: request);
    });
  }

  void scrollToBottom({int? request}) {
    final activeRequest = request ?? _scrollRequest;
    if (!mounted || activeRequest != _scrollRequest) return;

    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      final bottomExtent = position.minScrollExtent;
      if ((bottomExtent - position.pixels).abs() > 0.5) {
        _scrollController.jumpTo(bottomExtent);
      }
    }
  }

  List<_MessageRow> _buildRows() {
    final rows = <_MessageRow>[];
    String? currentDateKey;
    final messagesById = <String, Map<String, dynamic>>{};
    for (final message in widget.messages) {
      for (final key in ['id', 'sid']) {
        final id = message[key]?.toString().trim();
        if (id != null && id.isNotEmpty) messagesById[id] = message;
      }
    }

    for (final message in widget.messages) {
      final date = _asDate(message['dateSent'])?.toLocal();
      if (date == null) continue;

      final dateKey = DateFormat('yyyy-MM-dd').format(date);
      if (dateKey != currentDateKey) {
        rows.add(_MessageRow.header(dateKey));
        currentDateKey = dateKey;
      }
      final presentation = ConversationPresentationV1.fromMessage(message);
      final replyTo =
          message['replyTo']?.toString().trim() ?? presentation.replyToId;
      final quoted = replyTo == null ? null : messagesById[replyTo];
      if (quoted == null) {
        rows.add(_MessageRow.message(message));
      } else {
        final quotedPresentation =
            ConversationPresentationV1.fromMessage(quoted);
        final quotedText = quotedPresentation.text ??
            quotedPresentation.title ??
            quoted['message']?.toString();
        rows.add(
          _MessageRow.message({
            ...message,
            if (quotedText != null && quotedText.trim().isNotEmpty)
              'quotedText': quotedText.trim(),
            'quotedDirection': quoted['direction'],
          }),
        );
      }
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
    // A reversed chat list builds the newest row first and anchors it at the
    // bottom. Reversing the chronological row collection at the same time
    // preserves the expected visual order and keeps date headers above their
    // messages.
    final rows = _buildRows().reversed.toList(growable: false);

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
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
