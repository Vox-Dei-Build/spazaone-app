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
  final currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final StreamController<List<Map<String, dynamic>>> _controller =
      StreamController.broadcast();
  bool isDisposed = false;
  final ValueNotifier<bool> loadingNotifier = ValueNotifier(false);
  late TwilioService _twilioService;
  late BotpressService _botpressService;
  Timer? _fetchTimer;

  ConnectManagementViewModel(this.customerId) {
    _initializeTwilioService();
    _initializeBotpressService();
  }

  Future<void> _initializeTwilioService() async {
    _twilioService = await TwilioService.create();
  }

  Future<void> _initializeBotpressService() async {
    _botpressService = await BotpressService.create();
  }

  Stream<List<Map<String, dynamic>>> streamMessages() {
    _startFetchingMessages();
    return _controller.stream;
  }

  void _startFetchingMessages() {
    // ✅ Ensure no duplicate timers
    _fetchTimer?.cancel();

    _fetchMessages(customerId); // Start first fetch
    _fetchTimer = Timer.periodic(const Duration(seconds: 700), (timer) {
      if (isDisposed) {
        timer.cancel(); // ✅ Stop when disposed
      } else {
        _fetchMessages(customerId);
      }
    });
  }

  Future<void> _fetchMessages(String customerId) async {
    if (isDisposed) return; // ✅ Stop immediately if disposed

    try {
      final customerNumber =
          await fetchAndFormatPhoneNumber(currentUserId, customerId);

      // 🔥 Get Twilio Numbers from Remote Config
      final remoteConfigService = await RemoteConfigService.getInstance();
      final twilioSmsNumber = remoteConfigService.getString('TWILIO_NUMBER');
      final twilioMessagingServiceId =
          remoteConfigService.getString('TWILIO_MESSAGING_SERVICE_ID');

      //  🚨 No valid customer number found
      if (customerNumber == null) {
        _controller.add([]);
        return;
      }

      // 🔥 Fetch outgoing, incoming and Botpress messages
      final sentMessages = await _twilioService.fetchMessagesToCustomer(
        customerNumber: customerNumber,
        currentUserId: currentUserId,
        customerId: customerId,
      );

      final receivedMessages = await _twilioService.fetchMessagesFromCustomer(
        customerNumber: customerNumber,
        twilioSmsNumber: twilioSmsNumber,
        twilioMessagingServiceId: twilioMessagingServiceId,
      );

      final botpressMessages = await _botpressService.fetchBotpressMessages(
          customerNumber: customerNumber);

      final cutOffDate = DateTime(2024, 01, 01);

      // 🔥 Merge and dedupe messages
      final Map<String, Map<String, dynamic>> merged = {};
      for (final msg in [...sentMessages, ...receivedMessages, ...botpressMessages]) {
        final id = msg['sid'] ?? msg['id'] ??
            '${msg['dateSent']}-${msg['message']}';
        merged[id] = msg;
      }

      final allMessages = merged.values.where((msg) {
        final date = msg['dateSent'] is DateTime
            ? msg['dateSent'] as DateTime
            : DateTime.parse(msg['dateSent'].toString());
        return date.isAfter(cutOffDate);
      }).toList();

      for (final msg in allMessages) {
        final isWhatsApp = msg['isWhatsApp'] == true;
        msg['isWhatsApp'] = isWhatsApp;
        msg['isSMS'] = msg['isSMS'] ?? !isWhatsApp;
        msg['isAI'] = msg['isAI'] ?? (isWhatsApp && msg['direction'] == 'outbound');
      }

      allMessages.sort((a, b) {
        final dateA = a['dateSent'] is DateTime
            ? a['dateSent'] as DateTime
            : DateTime.parse(a['dateSent'].toString());
        final dateB = b['dateSent'] is DateTime
            ? b['dateSent'] as DateTime
            : DateTime.parse(b['dateSent'].toString());
        return dateA.compareTo(dateB);
      });

      if (!isDisposed) _controller.add(allMessages); // ✅ Only update if active
    } catch (e, stackTrace) {
      print("🔥 Error fetching messages: $e");
      print("📜 StackTrace: $stackTrace");
      if (!isDisposed) _controller.add([]);
    }
  }

  void markMessagesAsRead(String? customerNumber) async {
    try {
      await http.post(
        Uri.parse(
            "https://us-central1-pasella-ledger.cloudfunctions.net/markMessagesAsRead"),
        body: jsonEncode({
          "merchantId": currentUserId,
          "customerNumber": customerNumber,
        }),
        headers: {"Content-Type": "application/json"},
      );

      // Remove badge after marking messages as read
      FlutterAppBadger.removeBadge();
    } catch (e) {
      print("Error marking messages as read: $e");
    }
  }

  void dispose() {
    isDisposed = true;
    _fetchTimer?.cancel(); // ✅ Stop fetching immediately
    loadingNotifier.dispose();
    _controller.close();
  }
}
