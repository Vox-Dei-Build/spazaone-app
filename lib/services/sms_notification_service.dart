import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/services/sms_service.dart';
import 'package:pasella/templates/sms_message.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/phone_util.dart';

class SMSNotificationService {
  Future<void> sendFormattedSMS(
    String currentUserId,
    String customerId,
    String customerName,
    String message,
    String? mobileNumber,
  ) async {
    try {
      String? phoneNumber =
          await fetchAndFormatPhoneNumber(currentUserId, customerId);

      if (isValidSAPhoneNumber(phoneNumber) && phoneNumber != null) {
        final smsService = await SMSService.create();

        double balance = await CurrencyUtil.fetchCurrentBalanceForCustomer(
            currentUserId, customerId);

        String shopName =
            await fetchShopNameForUser(currentUserId) ?? 'The Corner Shop';

        message = message.replaceAll('{balance}', CurrencyUtil.format(balance));
        message = message.replaceAll('{shopName}', shopName);
        message = message.replaceAll('{customerName}', customerName);

        smsService.sendSMS(phoneNumber, message);

        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .collection('customers')
            .doc(customerId)
            .collection('reminders')
            .add({
          'message': message,
          'dateSent': Timestamp.now(),
        });
      }
    } catch (e) {
      print('Error while sending SMS, queuing for later: $e');
    }
  }

  Future<void> sendConfirmationSMS(
    String currentUserId,
    String customerId,
    String transactionType,
    double amount,
    String customerName,
    String? mobileNumber,
  ) async {
    try {
      String message = '';
      if (transactionType == 'Credit') {
        message = SMSMessages.creditConfirmationSMS
            .replaceAll('{customerName}', customerName)
            .replaceAll('{amount}', CurrencyUtil.format(amount));
      } else {
        message = SMSMessages.paymentConfirmationSMS
            .replaceAll('{customerName}', customerName)
            .replaceAll('{amount}', CurrencyUtil.format(amount));
      }

      await sendFormattedSMS(
          currentUserId, customerId, customerName, message, mobileNumber);
    } catch (e) {
      print('Error occurred while sending confirmation SMS: $e');
    }
  }

  Future<void> sendOnboardingSMS(
    String currentUserId,
    String customerId,
    String customerName,
    String? mobileNumber,
  ) async {
    try {
      await sendFormattedSMS(currentUserId, customerId, customerName,
          SMSMessages.onboardingSMS, mobileNumber);
    } catch (e) {
      print('Error occurred while sending confirmation SMS: $e');
    }
  }

  Future<void> sendReminderSMS(
    String currentUserId,
    String customerId,
    String customerName,
    String? mobileNumber,
  ) async {
    try {
      await sendFormattedSMS(currentUserId, customerId, customerName,
          SMSMessages.reminderSMS, mobileNumber);
    } catch (e) {
      print('Error occurred while sending confirmation SMS: $e');
    }
  }
}
