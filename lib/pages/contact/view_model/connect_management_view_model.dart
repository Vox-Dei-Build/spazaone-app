import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/services/twilio_service.dart';
import 'package:pasella/utils/phone_util.dart';

class ConnectManagementViewModel {
  final String customerId;

  final ValueNotifier<bool> loadingNotifier = ValueNotifier(false);
  late TwilioService _twilioService;

  ConnectManagementViewModel(this.customerId) {
    _initializeTwilioService();
  }

  Future<void> _initializeTwilioService() async {
    _twilioService = await TwilioService.create();
  }

  Stream<List<Map<String, dynamic>>> streamMessages() async* {
    await _initializeTwilioService();

    while (true) {
      try {
        final currentUserId = FirebaseAuth.instance.currentUser!.uid;
        final customerNumber =
            await fetchAndFormatPhoneNumber(currentUserId, customerId);

        // 🔥 Get Twilio Numbers from Remote Config
        final remoteConfigService = await RemoteConfigService.getInstance();
        final twilioSmsNumber = remoteConfigService.getString('TWILIO_NUMBER');
        final twilioMessagingServiceId =
            remoteConfigService.getString('TWILIO_MESSAGING_SERVICE_ID');

        if (customerNumber == null) {
          print("🚨 No valid customer number found");
          yield [];
          await Future.delayed(const Duration(seconds: 30));
          continue;
        }

        // 🔥 Fetch outgoing messages (Merchant → Customer)
        final sentMessages = await _twilioService.fetchMessagesToCustomer(
          customerNumber: customerNumber,
          twilioSmsNumber: twilioSmsNumber,
          twilioMessagingServiceId: twilioMessagingServiceId,
        );
        print("📩 Sent Messages: ${sentMessages.length}");

        // 🔥 Fetch incoming messages (Customer → Twilio)
        final receivedMessages = await _twilioService.fetchMessagesFromCustomer(
          customerNumber: customerNumber,
          twilioSmsNumber: twilioSmsNumber,
          twilioMessagingServiceId: twilioMessagingServiceId,
        );
        print("📩 Received Messages: ${receivedMessages.length}");

        // 🔥 Merge both types & sort by date (latest first)
        final allMessages = [...sentMessages, ...receivedMessages];
        allMessages.sort((a, b) => a['dateSent'].compareTo(b['dateSent']));

        print("✅ Merged Messages: ${allMessages.length}");
        yield allMessages;
      } catch (e, stackTrace) {
        print("🔥 Error fetching messages: $e");
        print("📜 StackTrace: $stackTrace");
        yield [];
      }

      await Future.delayed(const Duration(seconds: 300));
    }
  }

  void dispose() {
    loadingNotifier.dispose();
  }
}
