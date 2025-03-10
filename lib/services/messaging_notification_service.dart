import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/models/common/sms_event.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
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
  late final DynamicPricingService pricingService;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  MessagingNotificationService._(this.welcome_message, this.credit_transaction,
      this.payment_transaction, this.reminder_message, this.pricingService);

  static Future<MessagingNotificationService> create() async {
    final remoteConfigService = await RemoteConfigService.getInstance();
    final pricingService = await DynamicPricingService.initialize();

    return MessagingNotificationService._(
        remoteConfigService.getString('TWILIO_WELCOME_MESSAGE_TID'),
        remoteConfigService.getString('TWILIO_CREDIT_TRANSACTION_TID'),
        remoteConfigService.getString('TWILIO_PAYMENT_TRANSACTION_TID'),
        remoteConfigService.getString('TWILIO_REMINDER_MESSAGE_TID'),
        pricingService);
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
    double templateMessageCost,
  ) async {
    try {
      // Fetch required data in parallel
      final results = await Future.wait([
        fetchAndFormatPhoneNumber(currentUserId, customerId),
        fetchShopNameForUser(currentUserId),
        CurrencyUtil.fetchCurrentBalanceForCustomer(currentUserId, customerId),
      ]);

      String? phoneNumber = results[0] as String?;
      String shopName = results[1] as String? ?? 'Pasella';
      double balance = results[2] as double;
      String formattedBalance = CurrencyUtil.format(balance);

      if (phoneNumber == null || !isValidSAPhoneNumber(phoneNumber)) {
        eventBus.fire(SMSEvent("Invalid phone number.", success: false));
        return;
      }

      // 🔹 Check Firestore if the number supports WhatsApp
      final bool hasWhatsApp = await isWhatsAppEnabled(phoneNumber);
      final double messageCost = hasWhatsApp
          ? pricingService.whatsappUtilityPrice
          : templateMessageCost;

      Map<String, dynamic> variables = {
        "customerName": customerName,
        "amount": amount,
        "shopName": shopName,
        "balance": formattedBalance,
      };

      bool messageSent = false; // Track if any message was successfully sent

      // 🔹 Try WhatsApp First
      if (hasWhatsApp) {
        final WhatsAppMessagingService whatsappService =
            await WhatsAppMessagingService.create();

        String? messageId = await whatsappService.sendWhatsAppMessage(
            phoneNumber, templateSid, variables);

        if (messageId != null) {
          // Poll for delivery confirmation
          bool delivered = await whatsappService.pollMessageStatus(messageId);

          if (delivered) {
            eventBus.fire(SMSEvent(inAppNotificationMessage, success: true));
            messageSent = true;
            await deductBalance(currentUserId, messageCost);
          }
        }
      }

      // 🔹 If WhatsApp failed, fallback to SMS
      if (!messageSent) {
        await _sendSMSFallback(phoneNumber, message, formattedBalance, shopName,
            customerName, inAppNotificationMessage, currentUserId, messageCost);
      }

      // 🔹 Store the notification record in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .doc(customerId)
          .collection('reminders')
          .add({
        'message': message,
        'dateSent': Timestamp.now(),
        'phoneNumber': phoneNumber,
        'customer_details': variables,
        'messageCost': messageCost,
        'merchant': currentUserId
      });
    } catch (e) {
      print('Error while sending message: $e');
      eventBus.fire(SMSEvent(
          "Notification was unsuccessful, please try again later",
          success: false));
    }
  }

  Future<void> _sendSMSFallback(
      phoneNumber,
      message,
      formattedBalance,
      shopName,
      customerName,
      inAppNotificationMessage,
      currentUserId,
      messageCost) async {
    final SMSMessagingService messageService =
        await SMSMessagingService.create();

    message = message.replaceAll('{balance}', formattedBalance);
    message = message.replaceAll('{shopName}', shopName);
    message = message.replaceAll('{customerName}', customerName);

    await messageService.sendSMS(phoneNumber, message).then((statusCode) async {
      if (statusCode == 201) {
        await deductBalance(currentUserId, messageCost);
        eventBus.fire(SMSEvent(inAppNotificationMessage, success: true));
      } else {
        eventBus.fire(SMSEvent(
            "Notification was unsuccessful, please try again later",
            success: false));
      }
    });
  }

  Future<void> deductBalance(String merchantId, double cost) async {
    DocumentReference merchantRef =
        firestore.collection('users').doc(merchantId);

    await firestore.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(merchantRef);
      if (!snapshot.exists) return;

      double currentBalance = (snapshot['virtualBalance'] ?? 0).toDouble();
      double newBalance = currentBalance - cost;

      transaction.update(merchantRef, {'virtualBalance': newBalance});
    });
  }

  Future<bool> isWhatsAppEnabled(String phoneNumber) async {
    DocumentSnapshot snapshot = await firestore
        .collection('successfulWhatsAppNumbers')
        .doc(phoneNumber)
        .get();

    return snapshot.exists;
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
      double messageCost = 0.0;

      if (transactionType == 'Credit') {
        templateSid = credit_transaction;
        inAppNotification = InAppNotifications.creditTransactionNotification;
        message = SMSMessages.creditConfirmationSMS
            .replaceAll('{customerName}', customerName)
            .replaceAll('{amount}', CurrencyUtil.format(amount));
        messageCost = pricingService.smsReminderTemplatePrice;
      } else {
        templateSid = payment_transaction;
        inAppNotification = InAppNotifications.paymentTransactionNotification;
        message = SMSMessages.paymentConfirmationSMS
            .replaceAll('{customerName}', customerName)
            .replaceAll('{amount}', CurrencyUtil.format(amount));
        messageCost = pricingService.smsPaymentTemplatePrice;
      }

      await sendFormattedMessage(
          currentUserId,
          customerId,
          customerName,
          message,
          templateSid,
          mobileNumber,
          CurrencyUtil.format(amount),
          inAppNotification,
          messageCost);
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
          InAppNotifications.onboardingSuccessNotification,
          pricingService.smsReminderTemplatePrice);
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
          InAppNotifications.paymentReminderNotification,
          pricingService.smsReminderTemplatePrice);
    } catch (e) {
      print('Error occurred while sending confirmation SMS: $e');
    }
  }
}
