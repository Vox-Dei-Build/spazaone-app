import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:pasella/config/remote_config.dart';
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
  Timer? _fetchTimer;

  ConnectManagementViewModel(this.customerId) {
    _initializeTwilioService();
  }

  Future<void> _initializeTwilioService() async {
    _twilioService = await TwilioService.create();
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

      // 🔥 Fetch outgoing & incoming messages
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

      final cutOffDate = DateTime(2024, 01, 01);

      // 🔥 Merge, filter & sort messages
      // 🔥 Merge, filter, and sort messages
      final allMessages = [...sentMessages, ...receivedMessages].where((msg) {
        final dateString = msg['dateSent'].toString(); // Ensure it's a String
        final messageDate = DateTime.parse(dateString); // Convert to DateTime
        return messageDate.isAfter(cutOffDate);
      }).toList();

      allMessages.sort((a, b) {
        final dateA = DateTime.parse(a['dateSent'].toString());
        final dateB = DateTime.parse(b['dateSent'].toString());
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
