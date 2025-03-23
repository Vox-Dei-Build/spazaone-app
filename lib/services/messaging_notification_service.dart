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

      // Normalize number format for Firestore lookup
      String normalizedPhone = normalizePhoneNumber(phoneNumber);

      // Fetch existing WhatsApp status from Firestore
      final whatsappStatus = await fetchWhatsAppStatus(normalizedPhone);
      bool? hasWhatsApp = whatsappStatus?['hasWhatsApp'];
      DateTime? lastChecked = whatsappStatus?['lastChecked'];

      // If we've **never checked before** or it’s been over 30 days, force a WhatsApp test
      bool needsWhatsAppCheck = (lastChecked == null) ||
          (DateTime.now().difference(lastChecked).inDays > 30);

      bool messageSent = false; // Track if message was successfully sent

      // Try WhatsApp First if we need to check or we already know it works
      if (needsWhatsAppCheck || hasWhatsApp == true) {
        final WhatsAppMessagingService whatsappService =
            await WhatsAppMessagingService.create();

        String? messageId = await whatsappService
            .sendWhatsAppMessage(phoneNumber, templateSid, {
          "customerName": customerName,
          "amount": amount,
          "shopName": shopName,
          "balance": formattedBalance,
        });

        if (messageId != null) {
          // Fire and forget → Poll for delivery status in the background
          whatsappService.pollMessageStatus(messageId).then((delivered) async {
            if (delivered) {
              // If delivered, deduct balance and update Firestore
              await deductBalance(
                  currentUserId, pricingService.whatsappUtilityPrice);
              await storeWhatsAppCheck(normalizedPhone, true);
              await storeNotification(
                currentUserId: currentUserId,
                customerId: customerId,
                message: _generateRenderedMessage(message, {
                  "customerName": customerName,
                  "amount": amount,
                  "shopName": shopName,
                  "balance": formattedBalance,
                }),
                phoneNumber: phoneNumber,
                customerDetails: {
                  "customerName": customerName,
                  "amount": amount,
                  "shopName": shopName,
                  "balance": formattedBalance,
                },
                messageCost: pricingService.whatsappUtilityPrice,
                templateKey: templateSid,
                templateType: 'whatsapp',
              );

              eventBus.fire(SMSEvent(inAppNotificationMessage, success: true));
            } else {
              // If WhatsApp failed, store failure in Firestore
              await storeWhatsAppCheck(normalizedPhone, false);
            }
          });

          messageSent =
              true; // Assume message was sent since it's now being polled
        }
      }

      // If WhatsApp failed or user is confirmed not to have it, fallback to SMS
      if (!messageSent) {
        await _sendSMSFallback(
            phoneNumber,
            message,
            amount,
            formattedBalance,
            shopName,
            customerName,
            inAppNotificationMessage,
            currentUserId,
            templateMessageCost,
            customerId,
            templateSid, {
          "customerName": customerName,
          "amount": amount,
          "shopName": shopName,
          "balance": formattedBalance,
        });
      }
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
      amount,
      shopName,
      customerName,
      inAppNotificationMessage,
      currentUserId,
      messageCost,
      customerId,
      templateSid,
      variables) async {
    final SMSMessagingService messageService =
        await SMSMessagingService.create();

    message = message.replaceAll('{balance}', formattedBalance);
    message = message.replaceAll('{shopName}', shopName);
    message = message.replaceAll('{customerName}', customerName);

    await messageService.sendSMS(phoneNumber, message).then((statusCode) async {
      if (statusCode == 201) {
        await deductBalance(currentUserId, messageCost);

        await storeNotification(
          currentUserId: currentUserId,
          customerId: customerId,
          message: _generateRenderedMessage(message, {
            "customerName": customerName,
            "amount": amount,
            "shopName": shopName,
            "balance": formattedBalance,
          }),
          phoneNumber: phoneNumber,
          customerDetails: {
            "customerName": customerName,
            "amount": amount,
            "shopName": shopName,
            "balance": formattedBalance,
          },
          messageCost: pricingService.whatsappUtilityPrice,
          templateKey: templateSid,
          templateType: 'sms',
        );
        eventBus.fire(SMSEvent(inAppNotificationMessage, success: true));
      } else {
        eventBus.fire(SMSEvent(
            "Notification was unsuccessful, please try again later",
            success: false));
      }
    });
  }

  Future<void> deductBalance(String merchantId, double cost) async {
    DocumentReference walletRef = firestore
        .collection('users')
        .doc(merchantId)
        .collection('wallet')
        .doc('current');

    await firestore.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(walletRef);
      if (!snapshot.exists) return;

      double currentBalance = (snapshot['virtualBalance'] ?? 0).toDouble();
      double newBalance = currentBalance - cost;

      transaction.update(walletRef, {'virtualBalance': newBalance});
    });
  }

  String _generateRenderedMessage(
      String message, Map<String, String?> variables) {
    variables.forEach((key, value) {
      message = message.replaceAll('{{$key}}', value ?? '');
    });
    return message;
  }

  Future<void> storeNotification({
    required String currentUserId,
    required String customerId,
    required String message,
    required String phoneNumber,
    required Map<String, dynamic> customerDetails,
    required double messageCost,
    String? templateKey, // e.g. 'payment_transaction'
    String? templateType, // 'sms' or 'whatsapp'
  }) async {
    final notificationRef = FirebaseFirestore.instance
        .collection('notifications')
        .doc(currentUserId)
        .collection('customer_notifications');

    await notificationRef.add({
      'timestamp': FieldValue.serverTimestamp(),
      'message': message,
      'messageCost': messageCost,
      'merchant': currentUserId,
      'customer_details': customerDetails,
      'customer_phone': phoneNumber,
      'customer_id': customerId,
      'templateKey': templateKey,
      'templateType': templateType,
      'dateSent': Timestamp.now(),
    });
  }

  Future<Map<String, dynamic>?> fetchWhatsAppStatus(String phoneNumber) async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('successfulWhatsAppNumbers')
        .where('phoneNumber', isEqualTo: phoneNumber)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      final data = querySnapshot.docs.first.data();
      return {
        'hasWhatsApp': data['hasWhatsApp'] ?? false, // Ensure boolean value
        'lastChecked': (data['lastChecked'] as Timestamp?)?.toDate(),
      };
    }

    return null; // No record found → we've never checked before
  }

  Future<void> storeWhatsAppCheck(String phoneNumber, bool hasWhatsApp) async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('successfulWhatsAppNumbers')
        .where('phoneNumber', isEqualTo: phoneNumber)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      // Update existing record
      await querySnapshot.docs.first.reference.set({
        'hasWhatsApp': hasWhatsApp,
        'lastChecked': Timestamp.now(),
      }, SetOptions(merge: true));
    } else {
      // Create a new record
      await FirebaseFirestore.instance
          .collection('successfulWhatsAppNumbers')
          .add({
        'phoneNumber': phoneNumber,
        'hasWhatsApp': hasWhatsApp,
        'lastChecked': Timestamp.now(),
      });
    }
  }

  Future<bool> isWhatsAppEnabled(String phoneNumber) async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('successfulWhatsAppNumbers')
        .where('phoneNumber', isEqualTo: phoneNumber)
        .limit(1)
        .get();

    return querySnapshot.docs.isNotEmpty;
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
        message = SMSMessages.creditConfirmationShort
            .replaceAll('{customerName}', customerName)
            .replaceAll('{amount}', CurrencyUtil.format(amount));
        messageCost = pricingService.smsReminderTemplatePrice;
      } else {
        templateSid = payment_transaction;
        inAppNotification = InAppNotifications.paymentTransactionNotification;
        message = SMSMessages.paymentConfirmationShort
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
          SMSMessages.creditConfirmationShort,
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
          SMSMessages.reminderShort,
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
