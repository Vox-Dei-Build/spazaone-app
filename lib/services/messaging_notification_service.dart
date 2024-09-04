import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/models/common/sms_event.dart';
import 'package:pasella/services/sms_messaging_service.dart';
import 'package:pasella/services/whatsapp_messaging_service.dart';
import 'package:pasella/templates/in_app_notification.dart';
import 'package:pasella/templates/sms_message.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/phone_util.dart';

class MessagingNotificationService {
  late final String welcome_message;
  late final String credit_transaction;
  late final String payment_transaction;
  late final String reminder_message;

  MessagingNotificationService() {
    final remoteConfigService = RemoteConfigService.createInstance();
    welcome_message =
        remoteConfigService.getString('TWILIO_WELCOME_MESSAGE_TID')!;
    credit_transaction =
        remoteConfigService.getString('TWILIO_CREDIT_TRANSACTION_TID')!;
    payment_transaction =
        remoteConfigService.getString('TWILIO_PAYMENT_TRANSACTION_TID')!;
    reminder_message =
        remoteConfigService.getString('TWILIO_REMINDER_MESSAGE_TID')!;
  }

  Future<void> sendFormattedMessage(
    String currentUserId,
    String customerId,
    String customerName,
    String message,
    String templateSid,
    String? mobileNumber,
    String? amount,
    String inAppNotificationMessage,
  ) async {
    try {
      // Fetch phone number, shop name, and balance in parallel
      final phoneNumberFuture =
          fetchAndFormatPhoneNumber(currentUserId, customerId);
      final shopNameFuture = fetchShopNameForUser(currentUserId);
      final balanceFuture = CurrencyUtil.fetchCurrentBalanceForCustomer(
          currentUserId, customerId);

      // Await all the futures at once
      final results =
          await Future.wait([phoneNumberFuture, shopNameFuture, balanceFuture]);

      String? phoneNumber = results[0] as String?;
      String shopName = results[1] as String? ?? 'Pasella';
      double balance = results[2] as double;

      if (isValidSAPhoneNumber(phoneNumber) && phoneNumber != null) {
        final WhatsAppMessagingService whatsappService =
            WhatsAppMessagingService();

        String formattedBalance = CurrencyUtil.format(balance);

        Map<String, dynamic> variables = {
          "customerName": customerName,
          "amount": amount,
          "shopName": shopName,
          "balance": formattedBalance,
        };

        // Send WhatsApp message without waiting for the status
        String? messageId = await whatsappService.sendWhatsAppMessage(
            phoneNumber, templateSid, variables);

        if (messageId != null) {
          // Start polling in the background
          whatsappService.pollMessageStatus(messageId).then((delivered) {
            if (delivered) {
              eventBus.fire(SMSEvent(inAppNotificationMessage, success: true));
            } else {
              // Optionally send an SMS if WhatsApp failed
              _sendSMSFallback(phoneNumber, message, formattedBalance, shopName,
                  customerName, inAppNotificationMessage);
            }
          });
        } else {
          // Handle the failure to send the WhatsApp message
          _sendSMSFallback(phoneNumber, message, formattedBalance, shopName,
              customerName, inAppNotificationMessage);
        }

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
      } else {
        eventBus.fire(SMSEvent(
            "Notification was unsuccessful, please provide a valid number.",
            success: false));
      }
    } catch (e) {
      print('Error while sending SMS, queuing for later: $e');
      eventBus.fire(SMSEvent(
          "Notification was unsuccessful, please try again later",
          success: false));
    }
  }

  Future<void> _sendSMSFallback(phoneNumber, message, formattedBalance,
      shopName, customerName, inAppNotificationMessage) async {
    final SMSMessagingService messageService = SMSMessagingService.create();

    message = message.replaceAll('{balance}', formattedBalance);
    message = message.replaceAll('{shopName}', shopName);
    message = message.replaceAll('{customerName}', customerName);

    await messageService.sendSMS(phoneNumber, message).then((statusCode) => {
          if (statusCode == 201)
            {eventBus.fire(SMSEvent(inAppNotificationMessage, success: true))}
          else
            {
              eventBus.fire(SMSEvent(
                  "Notification was unsuccessful, please try again later",
                  success: false))
            }
        });
  }

  Future<void> sendConfirmationMessage(
    String currentUserId,
    String customerId,
    String transactionType,
    double amount,
    String customerName,
    String? mobileNumber,
  ) async {
    try {
      String message = '';
      String templateSid = '';
      String inAppNotification = '';
      if (transactionType == 'Credit') {
        templateSid = credit_transaction;
        inAppNotification = InAppNotifications.creditTransactionNotification;
        message = SMSMessages.creditConfirmationSMS
            .replaceAll('{customerName}', customerName)
            .replaceAll('{amount}', CurrencyUtil.format(amount));
      } else {
        templateSid = payment_transaction;
        inAppNotification = InAppNotifications.paymentTransactionNotification;
        message = SMSMessages.paymentConfirmationSMS
            .replaceAll('{customerName}', customerName)
            .replaceAll('{amount}', CurrencyUtil.format(amount));
      }

      await sendFormattedMessage(
          currentUserId,
          customerId,
          customerName,
          message,
          templateSid,
          mobileNumber,
          CurrencyUtil.format(amount),
          inAppNotification);
    } catch (e) {
      print('Error occurred while sending confirmation SMS: $e');
    }
  }

  Future<void> sendOnboardingMessage(
    String currentUserId,
    String customerId,
    String customerName,
    String? mobileNumber,
  ) async {
    try {
      String templateSid = welcome_message;
      await sendFormattedMessage(
          currentUserId,
          customerId,
          customerName,
          SMSMessages.onboardingSMS,
          templateSid,
          mobileNumber,
          '0',
          InAppNotifications.onboardingSuccessNotification);
    } catch (e) {
      print('Error occurred while sending confirmation SMS: $e');
    }
  }

  Future<void> sendReminderMessage(
    String currentUserId,
    String customerId,
    String customerName,
    String? mobileNumber,
  ) async {
    try {
      String templateSid = reminder_message;
      await sendFormattedMessage(
          currentUserId,
          customerId,
          customerName,
          SMSMessages.reminderSMS,
          templateSid,
          mobileNumber,
          '0',
          InAppNotifications.paymentReminderNotification);
    } catch (e) {
      print('Error occurred while sending confirmation SMS: $e');
    }
  }
}
