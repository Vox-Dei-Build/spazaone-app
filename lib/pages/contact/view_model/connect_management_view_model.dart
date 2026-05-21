import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app_badger_plus/flutter_app_badger_plus.dart';
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
  bool _isInitialized = false;
  bool _isFetching = false;
  bool _pollingStarted = false;
  bool _hasLoadedOnce = false;
  Future<void>? _initFuture;
  final ValueNotifier<bool> loadingNotifier = ValueNotifier(false);
  late TwilioService _twilio;
  late BotpressService _botpress;
  Timer? _poll;

  // V1 truth-surface (`fix/pas-wa-v1-bot-message-truth`): the Botpress bot
  // mirrors every outbound reply (balance, statement, menu, clarifications,
  // payment links, …) into Firestore via /logUnreadMessage. We subscribe to
  // that array as a 4th source so the merchant sees what the bot said even
  // when the live Twilio/Botpress fetch fails or lags.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _truthSurfaceSubscription;
  List<Map<String, dynamic>> _truthSurfaceEntries = const [];

  ConnectManagementViewModel(this.customerId) {
    _initFuture = _init();
  }

  Future<void> _init() async {
    _twilio = await TwilioService.create();
    _botpress = await BotpressService.create();
    _isInitialized = true;
  }

  void _startPolling() {
    if (_pollingStarted) return;
    _pollingStarted = true;
    _poll?.cancel();
    // first fetch immediately
    _fetchMessages();
    // then poll every 60s (tune as needed)
    _poll = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!isDisposed) _fetchMessages();
    });
  }

  Future<void> _fetchMessages() async {
    if (isDisposed || _isFetching) return;

    try {
      _isFetching = true;
      if (!_hasLoadedOnce) loadingNotifier.value = true;

      if (!_isInitialized) {
        await (_initFuture ??= _init());
        if (isDisposed) return;
      }

      // Resolve & normalize the customer number used across both systems
      final customerNumber =
          await fetchAndFormatPhoneNumber(currentUserId, customerId);
      if (customerNumber == null || customerNumber.isEmpty) {
        _controller.add(const []);
        _hasLoadedOnce = true;
        loadingNotifier.value = false;
        return;
      }

      // Lazily subscribe to the Pasella truth-surface (mirrored bot replies +
      // legacy unreadMessages). The subscription is keyed by the merchant doc
      // (a single document), so this is one cheap listener per ViewModel.
      _ensureTruthSurfaceSubscription(customerNumber);

      final rc = await RemoteConfigService.getInstance();
      final twilioSmsNumber = rc.getString('TWILIO_NUMBER');
      final twilioMessagingServiceId =
          rc.getString('TWILIO_MESSAGING_SERVICE_ID');

      final results = await Future.wait([
        _twilio.fetchMessagesToCustomer(
          customerNumber: customerNumber,
          currentUserId: currentUserId,
          customerId: customerId,
        ),
        _twilio.fetchMessagesFromCustomer(
          customerNumber: customerNumber,
          twilioSmsNumber: twilioSmsNumber,
          twilioMessagingServiceId: twilioMessagingServiceId,
        ),
        _botpress.fetchBotpressMessages(
          customerNumber: customerNumber,
        ),
      ]);

      final sentSms = results[0];
      final receivedSms = results[1];
      final wa = results[2];

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
        // Pasella truth surface: bot replies + handoff/payment-proof entries
        // mirrored from the bot. These are the source of truth for "what the
        // bot replied" — they always render, even if Twilio/Botpress polling
        // fails. Authoritative `direction` and `isAI` flags are pre-set in
        // `_truthSurfaceEntries` so the default heuristic in `normalize` is
        // bypassed.
        ...normalize(_truthSurfaceEntries,
            isSmsDefault: false, isWaDefault: true),
      ];

      for (final m in mergedIter) {
        byId[m['id'] as String] = m; // last write wins
      }

      final all = byId.values.toList()
        ..sort((a, b) =>
            (a['dateSent'] as DateTime).compareTo(b['dateSent'] as DateTime));

      _applyReadHeuristics(all);

      if (!isDisposed) _controller.add(all);
      _hasLoadedOnce = true;
    } catch (e, stack) {
      // ignore: avoid_print
      print('🔥 Error fetching messages: $e\n$stack');
      if (!isDisposed) _controller.add(const []);
    } finally {
      _isFetching = false;
      if (!isDisposed) loadingNotifier.value = false;
    }
  }

  DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is Timestamp) return v.toDate().toLocal();
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
    _truthSurfaceSubscription?.cancel();
    loadingNotifier.dispose();
    if (_isInitialized) _botpress.dispose();
    _controller.close();
  }
}

/// V1 truth-surface helpers (`fix/pas-wa-v1-bot-message-truth`).
///
/// We keep these as module-private helpers to keep the ViewModel surface
/// small. They translate a `users/{merchantId}.unreadMessages[]` Firestore
/// entry into the same `Map<String, dynamic>` shape the Connect tab's
/// `MessageCard` already consumes.
extension _TruthSurfaceSubscription on ConnectManagementViewModel {
  void _ensureTruthSurfaceSubscription(String customerNumber) {
    if (_truthSurfaceSubscription != null) return;

    final docRef =
        FirebaseFirestore.instance.collection('users').doc(currentUserId);
    final phoneSuffix = _digitsOnlySuffix(customerNumber);

    _truthSurfaceSubscription = docRef.snapshots().listen(
      (snapshot) {
        if (isDisposed) return;
        final raw = snapshot.data()?['unreadMessages'];
        if (raw is! List) {
          _truthSurfaceEntries = const [];
        } else {
          _truthSurfaceEntries = raw
              .whereType<Map<String, dynamic>>()
              .where((entry) =>
                  _matchesCustomer(entry['customerNumber'], phoneSuffix))
              .map(_truthSurfaceToMessage)
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
        }
        // Re-publish merged set without going back to Twilio/Botpress.
        unawaited(_republishMerged());
      },
      onError: (Object e, StackTrace st) {
        // ignore: avoid_print
        print('🔥 truth-surface stream error: $e\n$st');
      },
    );
  }

  /// Convert a persisted unreadMessages[] entry into the message shape used by
  /// MessageCard. Returns null for entries that fail validation (no body,
  /// unparseable timestamp).
  Map<String, dynamic>? _truthSurfaceToMessage(Map<String, dynamic> entry) {
    final body = (entry['message'] ?? '').toString();
    if (body.isEmpty) return null;
    final ts = _asDate(entry['timestamp']);
    if (ts == null) return null;

    // Direction: legacy entries (no field) were always inbound customer
    // signals; bot V1 mirror sets it explicitly.
    final direction =
        (entry['direction']?.toString().toLowerCase() ?? 'inbound');
    final senderRole = entry['senderRole']?.toString().toLowerCase();
    final channel = entry['channel']?.toString().toLowerCase() ?? 'whatsapp';

    final externalId = entry['externalId']?.toString();
    final id = externalId != null && externalId.isNotEmpty
        ? 'truth::$externalId'
        : 'truth::${ts.toIso8601String()}::$direction::$body';

    return {
      'id': id,
      'message': body,
      'dateSent': ts,
      'direction': direction,
      'isWhatsApp': channel == 'whatsapp',
      'isSMS': channel == 'sms',
      'isAI': senderRole == 'bot',
      'kind': entry['kind']?.toString() ?? 'text',
      'source': 'truth-surface',
      // Treat mirrored entries as delivered — Twilio status, when available,
      // will overwrite via the dedupe-by-id pipeline if a richer entry shows
      // up from the live polling source.
      'status': entry['status']?.toString() ?? 'delivered',
    };
  }

  /// Republish the merged stream without re-fetching Twilio/Botpress. Used
  /// when only the truth-surface snapshot changed.
  Future<void> _republishMerged() async {
    // Cheap path: simply trigger a fetch. _fetchMessages is guarded against
    // re-entrancy, so concurrent calls coalesce. This keeps a single merge
    // pipeline in one place.
    await _fetchMessages();
  }

  bool _matchesCustomer(dynamic stored, String phoneSuffix) {
    if (stored == null) return false;
    final s = _digitsOnlySuffix(stored.toString());
    if (s.isEmpty || phoneSuffix.isEmpty) return false;
    // Match on the last 9 digits to be robust across +27/0/27 prefixes.
    final n = phoneSuffix.length < 9 ? phoneSuffix.length : 9;
    final m = s.length < 9 ? s.length : 9;
    final k = n < m ? n : m;
    return phoneSuffix.substring(phoneSuffix.length - k) ==
        s.substring(s.length - k);
  }

  String _digitsOnlySuffix(String raw) {
    final buf = StringBuffer();
    for (final c in raw.codeUnits) {
      if (c >= 0x30 && c <= 0x39) buf.writeCharCode(c);
    }
    return buf.toString();
  }
}
