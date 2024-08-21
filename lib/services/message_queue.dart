import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/models/common/queued_sms.dart';
import 'package:pasella/models/common/sms_event.dart';
import 'package:pasella/services/sms_messaging_service.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/phone_util.dart';

List<SMSRequest> smsQueue = [];

class SMSRequest {
  final String phoneNumber;
  final String message;
  final String currentUserId;
  final String customerId;
  final String customerName;
  final double? amount;

  SMSRequest(
      {required this.phoneNumber,
      required this.message,
      required this.currentUserId,
      required this.customerId,
      required this.customerName,
      this.amount});
}

void queueSMSMessage(String phoneNumber, String message, String currentUserId,
    String customerId, String customerName, double? amount) async {
  Box<QueuedSMS> box =
      Hive.box<QueuedSMS>('smsQueue'); // Directly access the box
  final queuedSMS = QueuedSMS(
    phoneNumber: phoneNumber,
    message: message,
    currentUserId: currentUserId,
    customerId: customerId,
    customerName: customerName,
    amount: amount,
  );
  await box.add(queuedSMS);
  eventBus.fire(SMSEvent(
      'No internet connection. SMS queued for later delivery',
      success: true));
}

Future<void> sendQueuedSMSMessages(SMSMessagingService smsService) async {
  final Box<QueuedSMS> box = Hive.box<QueuedSMS>('smsQueue');
  List<dynamic> keysToRemove = [];

  for (var i = 0; i < box.length; i++) {
    var key = box.keyAt(i);
    var sms = box.get(key);
    if (sms != null) {
      var success = await sendWithRetries(smsService, sms, 3);

      if (success) {
        keysToRemove.add(key); // Collect keys of successfully sent messages
      }
    }
  }

  // Remove successfully sent messages from the box
  await box.deleteAll(keysToRemove);
}

Future<bool> sendWithRetries(
    SMSMessagingService smsService, QueuedSMS sms, int maxRetries) async {
  int attempt = 0;
  Duration delay = Duration(seconds: 60);

  while (attempt < maxRetries) {
    try {
      double balance = 0.0;
      if (sms.customerId != '') {
        // Fetch the latest data based on sms.currentUserId and sms.customerId
        balance = await CurrencyUtil.fetchCurrentBalanceForCustomer(
            sms.currentUserId, sms.customerId);
      }

      String shopName =
          await fetchShopNameForUser(sms.currentUserId) ?? 'The Corner Shop';

      // Construct the message using the latest data and the identified template
      String message = constructMessageFromTemplate(sms, balance, shopName);

      await smsService.sendSMS(sms.phoneNumber, message);
      eventBus.fire(SMSEvent("SMS to ${sms.phoneNumber} sent successfully.",
          success: true));
      return true; // Success, exit the loop
    } catch (e) {
      attempt++;
      print("Attempt $attempt failed, error: $e");

      if (attempt >= maxRetries) {
        eventBus.fire(SMSEvent(
            "Failed to send SMS to ${sms.phoneNumber} after $maxRetries attempts.",
            success: false));
      }

      await Future.delayed(delay);
      delay *= 2; // Double the delay for the next attempt
    }
  }
  return false; // All attempts failed
}

String constructMessageFromTemplate(
    QueuedSMS sms, double balance, String shopName) {
  String template = sms.message;

  // Replace placeholders with actual values
  return template
      .replaceAll("{balance}", CurrencyUtil.format(balance))
      .replaceAll("{shopName}", shopName)
      .replaceAll("{customerName}", sms.customerName)
      .replaceAll('{amount}',
          sms.amount != null ? CurrencyUtil.format(sms.amount!) : 'R0.0');
}
