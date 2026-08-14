import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/conversation/conversation_presentation.dart';
import 'message_card.dart';

class MessagesListView extends StatefulWidget {
  final List<Map<String, dynamic>> messages;
  final String? profileImageUrl;
  final String customerName;
  final ConversationPresentationV1 Function(Map<String, dynamic>)
      presentationParser;

  const MessagesListView({
    super.key,
    required this.messages,
    this.profileImageUrl,
    required this.customerName,
    this.presentationParser = ConversationPresentationV1.fromMessage,
  });

  @override
  State<MessagesListView> createState() => _MessagesListViewState();
}

class _MessagesListViewState extends State<MessagesListView> {
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = 0;
  int _scrollRequest = 0;
  String _latestMessageKey = '';
  List<_MessageRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _lastMessageCount = widget.messages.length;
    _latestMessageKey = _messageKey(widget.messages);
    _rows = _buildRows(widget.messages).reversed.toList(growable: false);
    _scheduleScrollToBottom();
  }

  @override
  void didUpdateWidget(covariant MessagesListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final latestMessageKey = _messageKey(widget.messages);
    if (!identical(oldWidget.messages, widget.messages)) {
      _rows = _buildRows(widget.messages).reversed.toList(growable: false);
    }
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

  List<_MessageRow> _buildRows(List<Map<String, dynamic>> messages) {
    final rows = <_MessageRow>[];
    String? currentDateKey;
    final messagesById = <String, Map<String, dynamic>>{};
    final preparedMessages = <Map<String, dynamic>>[];

    // Normalize each rich presentation once per stream emission. MessageCard
    // receives the cached model and the build method stays proportional to
    // the small number of visible bubbles rather than the whole history.
    for (final message in messages) {
      final prepared = <String, dynamic>{
        ...message,
        'presentationModel': widget.presentationParser(message),
      };
      preparedMessages.add(prepared);
      for (final key in ['id', 'sid']) {
        final id = prepared[key]?.toString().trim();
        if (id != null && id.isNotEmpty) messagesById[id] = prepared;
      }
    }

    for (final message in preparedMessages) {
      final date = _asDate(message['dateSent'])?.toLocal();
      if (date == null) continue;

      final dateKey = _dateKey(date);
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
            quoted['presentationModel'] as ConversationPresentationV1;
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

  String _dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

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
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      itemCount: _rows.length,
      itemBuilder: (context, index) {
        final row = _rows[index];
        if (row.dateKey != null) {
          return KeyedSubtree(
            key: ValueKey('date:${row.dateKey}'),
            child: _buildDateHeader(_formatDate(row.dateKey!)),
          );
        }
        return MessageCard(
          row.message!,
          key: ValueKey(row.stableKey),
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
  final String stableKey;

  const _MessageRow._({
    this.dateKey,
    this.message,
    required this.stableKey,
  });

  factory _MessageRow.header(String dateKey) =>
      _MessageRow._(dateKey: dateKey, stableKey: 'date:$dateKey');

  factory _MessageRow.message(Map<String, dynamic> message) {
    final id = message['id'] ?? message['sid'];
    final fallback = Object.hash(
      message['dateSent'],
      message['direction'],
      message['message'],
    );
    return _MessageRow._(
      message: message,
      stableKey: 'message:${id ?? fallback}',
    );
  }
}
