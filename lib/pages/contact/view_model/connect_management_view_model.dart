import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/services/twilio_service.dart';
import 'package:pasella/utils/phone_util.dart';

class ConnectManagementViewModel {
  final String customerId;
  final StreamController<List<Map<String, dynamic>>> _controller =
      StreamController.broadcast();
  bool isDisposed = false;
  final ValueNotifier<bool> loadingNotifier = ValueNotifier(false);
  late TwilioService _twilioService;
  Timer? _fetchTimer; // ✅ Store Timer reference

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
      final currentUserId = FirebaseAuth.instance.currentUser!.uid;
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

      // 🔥 Merge & sort messages
      final allMessages = [...sentMessages, ...receivedMessages];
      allMessages.sort((a, b) => a['dateSent'].compareTo(b['dateSent']));
      if (!isDisposed) _controller.add(allMessages); // ✅ Only update if active
    } catch (e, stackTrace) {
      print("🔥 Error fetching messages: $e");
      print("📜 StackTrace: $stackTrace");
      if (!isDisposed) _controller.add([]);
    }
  }

  void dispose() {
    isDisposed = true;
    _fetchTimer?.cancel(); // ✅ Stop fetching immediately
    loadingNotifier.dispose();
    _controller.close();
  }
}
