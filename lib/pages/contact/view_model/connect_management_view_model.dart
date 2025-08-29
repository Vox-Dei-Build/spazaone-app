import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/services/botpress_service.dart';
import 'package:pasella/services/twilio_service.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:http/http.dart' as http;

class ConnectManagementViewModel {
  final String customerId;
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;

  final _controller = StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> streamMessages() {
    _startPolling();
    return _controller.stream;
  }

  bool isDisposed = false;
  final ValueNotifier<bool> loadingNotifier = ValueNotifier(false);
  late TwilioService _twilio;
  late BotpressService _botpress;
  Timer? _poll;

  ConnectManagementViewModel(this.customerId) {
    _init();
  }

  Future<void> _init() async {
    _twilio = await TwilioService.create();
    _botpress = await BotpressService.create();
  }

  void _startPolling() {
    _poll?.cancel();
    // first fetch immediately
    _fetchMessages();
    // then poll every 60s (tune as needed)
    _poll = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!isDisposed) _fetchMessages();
    });
  }

  Future<void> _fetchMessages() async {
    if (isDisposed) return;

    try {
      loadingNotifier.value = true;

      // Resolve & normalize the customer number used across both systems
      final customerNumber =
          await fetchAndFormatPhoneNumber(currentUserId, customerId);
      if (customerNumber == null || customerNumber.isEmpty) {
        _controller.add(const []);
        loadingNotifier.value = false;
        return;
      }

      final rc = await RemoteConfigService.getInstance();
      final twilioSmsNumber = rc.getString('TWILIO_NUMBER');
      final twilioMessagingServiceId =
          rc.getString('TWILIO_MESSAGING_SERVICE_ID');

      // 1) Twilio SMS (existing functions). Make sure they return maps with:
      //    id/sid, message, dateSent (DateTime), direction, isSMS=true
      final sentSms = await _twilio.fetchMessagesToCustomer(
        customerNumber: customerNumber,
        currentUserId: currentUserId,
        customerId: customerId,
      );

      final receivedSms = await _twilio.fetchMessagesFromCustomer(
        customerNumber: customerNumber,
        twilioSmsNumber: twilioSmsNumber,
        twilioMessagingServiceId: twilioMessagingServiceId,
      );

      // 2) Botpress WhatsApp
      final wa = await _botpress.fetchBotpressMessages(
        customerNumber: customerNumber,
      );

      // ---- Merge + Dedupe ----
      final cutOff = DateTime(2024, 1, 1);
      final byId = <String, Map<String, dynamic>>{};

      Iterable<Map<String, dynamic>> normalize(List<Map<String, dynamic>> src,
          {required bool isSmsDefault, required bool isWaDefault}) sync* {
        for (final m in src) {
          final id = (m['sid'] ?? m['id'] ?? _compositeKey(m)).toString();
          final date = _asDate(m['dateSent']);
          if (date == null || date.isBefore(cutOff)) continue;

          final isWhatsApp = (m['isWhatsApp'] as bool?) ?? isWaDefault;
          final isSMS = (m['isSMS'] as bool?) ?? isSmsDefault;

          // Default isAI: WhatsApp outbound likely bot; SMS outbound likely agent
          final isAI = (m['isAI'] as bool?) ??
              (isWhatsApp && (m['direction']?.toString() == 'outbound'));

          yield {
            ...m,
            'id': id,
            'dateSent': date,
            'isWhatsApp': isWhatsApp,
            'isSMS': isSMS,
            'isAI': isAI,
          };
        }
      }

      final mergedIter = <Map<String, dynamic>>[
        ...normalize(sentSms, isSmsDefault: true, isWaDefault: false),
        ...normalize(receivedSms, isSmsDefault: true, isWaDefault: false),
        ...normalize(wa, isSmsDefault: false, isWaDefault: true),
      ];

      for (final m in mergedIter) {
        byId[m['id'] as String] = m; // last write wins
      }

      final all = byId.values.toList()
        ..sort((a, b) =>
            (a['dateSent'] as DateTime).compareTo(b['dateSent'] as DateTime));

      _applyReadHeuristics(all);

      if (!isDisposed) _controller.add(all);
    } catch (e, stack) {
      // ignore: avoid_print
      print('🔥 Error fetching messages: $e\n$stack');
      if (!isDisposed) _controller.add(const []);
    } finally {
      if (!isDisposed) loadingNotifier.value = false;
    }
  }

  DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _compositeKey(Map<String, dynamic> m) {
    final t = (m['dateSent'] is DateTime)
        ? (m['dateSent'] as DateTime).toIso8601String()
        : m['dateSent']?.toString() ?? '';
    final body = m['message']?.toString() ?? '';
    final dir = m['direction']?.toString() ?? '';
    return '$t::$dir::$body';
  }

  /// Best-effort mark-as-read hook
  Future<void> markMessagesAsRead(String? customerNumber) async {
    if (customerNumber == null) return;
    try {
      await http.post(
        Uri.parse(
            'https://us-central1-pasella-ledger.cloudfunctions.net/markMessagesAsRead'),
        body: jsonEncode({
          'merchantId': currentUserId,
          'customerNumber': customerNumber,
        }),
        headers: {'Content-Type': 'application/json'},
      );
      FlutterAppBadger.removeBadge();
    } catch (e) {
      // ignore: avoid_print
      print('markMessagesAsRead failed: $e');
    }
  }

  void _applyReadHeuristics(List<Map<String, dynamic>> msgs) {
    print('🟡 [_applyReadHeuristics] Start: ${msgs.length} messages');

    // --- Sort oldest → newest ---
    msgs.sort((a, b) =>
        (a['dateSent'] as DateTime).compareTo(b['dateSent'] as DateTime));
    print('🔄 Sorted by date');

    // --- Index for O(1) lookups ---
    final byId = <String, Map<String, dynamic>>{
      for (final m in msgs) (m['id'] as String): m
    };

    // --- 1) Incoming ⇒ read ---
    for (final m in msgs) {
      if (m['direction'] == 'inbound') {
        m['isRead'] = true;
        m['readReason'] = 'incoming';
        m['readAt'] = m['dateSent'];
        print('✅ incoming → read: id=${m['id']} at ${m['readAt']}');
      } else {
        m['isRead'] = m['isRead'] ?? false;
      }
    }

    // --- 2) Exact reply links (Botpress whatsapp:replyTo) ---
    for (final m in msgs) {
      if (m['direction'] == 'inbound') {
        final replyTo = m['replyTo']?.toString();
        if (replyTo != null && byId.containsKey(replyTo)) {
          final out = byId[replyTo]!;
          if (out['direction'] == 'outbound') {
            out['isRead'] = true;
            out['readReason'] = 'replyTo';
            out['readAt'] = m['dateSent'];
            print(
                '🔗 replyTo → read: outId=${out['id']} via inId=${m['id']} at ${out['readAt']}');
          }
        }
      }
    }

    // --- 3) Fallback: any later inbound within 48h → inferred read ---
    const fallbackWindow = Duration(hours: 48);

    DateTime? _nextInboundAfter(DateTime t, {required bool requireWhatsApp}) {
      for (final m in msgs) {
        if (m['direction'] == 'inbound') {
          final dt = m['dateSent'] as DateTime;
          if (dt.isAfter(t)) {
            if (!requireWhatsApp || (m['isWhatsApp'] == true)) return dt;
          }
        }
      }
      return null;
    }

    for (final m in msgs) {
      if (m['direction'] != 'outbound' || m['isRead'] == true) continue;
      final sentAt = m['dateSent'] as DateTime;
      final requireWa = m['isWhatsApp'] == true;

      final nextIn = _nextInboundAfter(sentAt, requireWhatsApp: requireWa);
      if (nextIn != null && nextIn.difference(sentAt) <= fallbackWindow) {
        m['isRead'] = true;
        m['readReason'] = 'inferred';
        m['readAt'] = nextIn;
        print('🤔 inferred → read: id=${m['id']} (next inbound $nextIn)');
      }
    }

    // --- 4) NEW: Anchor backfill from Twilio WhatsApp "read" statuses ---
// If any outbound WA message has status == 'read', assume nearby WA outgoing
// messages were seen as well.
    const backfillBefore = Duration(days: 30); // 👈 one month before anchor
    const backfillAfter = Duration(hours: 2); // still allow a little after
    final anchors = msgs.where((m) {
      final isOutbound = m['direction'] == 'outbound';
      final isWA = m['isWhatsApp'] == true;
      final status = (m['status'] ?? '').toString().toLowerCase();
      return isOutbound && isWA && status == 'read';
    }).toList();

    if (anchors.isNotEmpty) {
      print('📌 Found ${anchors.length} read anchors (Twilio WA "read")');
    }

    for (final a in anchors) {
      final anchorTime = a['readAt'] is DateTime
          ? a['readAt'] as DateTime
          : (a['dateSent'] as DateTime);
      final windowStart = anchorTime.subtract(backfillBefore);
      final windowEnd = anchorTime.add(backfillAfter);

      for (final m in msgs) {
        if (m['isRead'] == true) continue;
        if (m['direction'] != 'outbound') continue;
        if (m['isWhatsApp'] != true) continue;

        final t = m['dateSent'] as DateTime;
        if (!t.isBefore(windowStart) && !t.isAfter(windowEnd)) {
          m['isRead'] = true;
          m['readReason'] = 'twilio-anchor';
          m['readAt'] = anchorTime;
          print('📎 backfill via anchor → read: id=${m['id']} '
              '(anchorId=${a['id']}, window: $windowStart → $windowEnd, anchorAt=$anchorTime)');
        }
      }
    }

    // --- Summary ---
    final readCount = msgs.where((m) => m['isRead'] == true).length;
    print('📊 Heuristics done: $readCount/${msgs.length} marked read');
  }

  void dispose() {
    isDisposed = true;
    _poll?.cancel();
    loadingNotifier.dispose();
    _botpress.dispose();
    _controller.close();
  }
}
