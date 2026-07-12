import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/models/common/sms_event.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/services/sms_messaging_service.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/services/whatsapp_messaging_service.dart';
import 'package:pasella/shared/billing/cost_breakdown.dart';
import 'package:pasella/templates/in_app_notification.dart';
import 'package:pasella/templates/sms_message.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

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
    String? smsMessageOverride,
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
      // SMS-safe formatting: avoids U+00A0 thousands separator from
      // NumberFormat('en_ZA') which would force UCS-2 segmentation on any
      // body containing the balance (and silently double the SMS segment
      // count for balances >= R1 000). The WhatsApp template variables
      // below intentionally keep the locale-formatted value because
      // WhatsApp does not have GSM-7/UCS-2 segmentation.
      String formattedBalance = CurrencyUtil.formatForSms(balance);
      String formattedBalanceDisplay = CurrencyUtil.format(balance);

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
          "balance": formattedBalanceDisplay,
        });

        if (messageId != null) {
          // Fire and forget → Poll for delivery status in the background
          whatsappService.pollMessageStatus(messageId).then((outcome) async {
            if (outcome == WhatsAppDeliveryOutcome.delivered) {
              // WhatsApp delivery confirmed by Twilio poll. This is the
              // billable event -- balance is deducted in the same block, so
              // CommsSent fires exactly when the merchant is charged.
              await TelemetryService.instance.capture(CommsSent(
                channel: 'whatsapp',
                templateId: templateSid,
                recipientCount: 1,
              ));
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
                  "balance": formattedBalanceDisplay,
                }),
                phoneNumber: phoneNumber,
                customerDetails: {
                  "customerName": customerName,
                  "amount": amount,
                  "shopName": shopName,
                  "balance": formattedBalanceDisplay,
                },
                messageCost: pricingService.whatsappUtilityPrice,
                templateKey: templateSid,
                templateType: 'whatsapp',
              );

              eventBus.fire(SMSEvent(inAppNotificationMessage, success: true));
            } else if (shouldFallbackToSmsForStatus(outcome)) {
              // Only a definitive provider failure may trigger SMS fallback.
              // A transient status-poll/auth/network error is not proof that
              // WhatsApp failed: the accepted WhatsApp can still arrive and
              // would otherwise be followed by a duplicate SMS.
              await storeWhatsAppCheck(normalizedPhone, false);
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
                  smsMessageOverride,
                  customerId,
                  templateSid, {
                "customerName": customerName,
                "amount": amount,
                "shopName": shopName,
                "balance": formattedBalance,
              });
            } else {
              await CrashService.instance.recordNonFatal(
                'WhatsApp send accepted but delivery could not be confirmed',
                StackTrace.current,
                reason: 'WhatsApp delivery status unknown; SMS suppressed',
                context: {'template_id': templateSid},
              );
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
            smsMessageOverride,
            customerId,
            templateSid, {
          "customerName": customerName,
          "amount": amount,
          "shopName": shopName,
          "balance": formattedBalance,
        });
      }
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'sendFormattedMessage failed',
      );
      eventBus.fire(SMSEvent(
          "Notification was unsuccessful, please try again later",
          success: false));
    }
  }

  @visibleForTesting
  static bool shouldFallbackToSmsForStatus(
      WhatsAppDeliveryOutcome outcome) {
    return outcome == WhatsAppDeliveryOutcome.failed;
  }

  Future<void> _sendSMSFallback(
      phoneNumber,
      message,
      amount,
      formattedBalance,
      shopName,
      customerName,
      inAppNotificationMessage,
      currentUserId,
      messageCost,
      smsMessageOverride,
      customerId,
      templateSid,
      variables) async {
    final SMSMessagingService messageService =
        await SMSMessagingService.create();

    final smsMessage = (smsMessageOverride ?? message)
        .replaceAll('{balance}', formattedBalance)
        .replaceAll('{shopName}', shopName)
        .replaceAll('{customerName}', customerName);
    final smsCost = SMSPricingUtil.calculateCost(
      text: smsMessage,
      unitCost: (messageCost as num).toDouble(),
    );

    await messageService.sendSMS(phoneNumber, smsMessage).then((statusCode) async {
      if (statusCode == 201) {
        // Twilio accepted the SMS for delivery (201). We treat acceptance as
        // the billable signal because the SMS layer does not surface a later
        // delivery callback; balance is deducted on the same branch.
        await TelemetryService.instance.capture(CommsSent(
          channel: 'sms',
          templateId: templateSid,
          recipientCount: 1,
        ));
        await deductBalance(currentUserId, smsCost);

        await storeNotification(
          currentUserId: currentUserId,
          customerId: customerId,
          message: _generateRenderedMessage(smsMessage, {
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
          messageCost: smsCost,
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
        .where('hasWhatsApp', isEqualTo: true)
        .limit(1)
        .get();

    return querySnapshot.docs.isNotEmpty;
  }

  /// Predict which channel `sendFormattedMessage` is likely to use for
  /// `phoneNumber`, mirroring the dispatch logic exactly so the cost
  /// confirmation sheet can quote the right primary price.
  ///
  /// Static because it has no dependency on remote config or pricing —
  /// just a Firestore lookup against `successfulWhatsAppNumbers`. This
  /// lets cost-sheet callsites use it without paying the cost of a full
  /// `MessagingNotificationService.create()` (which initialises remote
  /// config + dynamic pricing) just to ask "is this number on WhatsApp?".
  ///
  /// Rules (must stay in lockstep with the WhatsApp-first branch in
  /// `sendFormattedMessage`):
  ///
  ///   * No record on file → WhatsApp will be tried first → `unknown`.
  ///   * Record + `hasWhatsApp == true` → WhatsApp expected.
  ///   * Record + `hasWhatsApp == false` + `lastChecked` within 30 days
  ///     → SMS expected (no recheck due).
  ///   * Record + `hasWhatsApp == false` + `lastChecked` > 30 days →
  ///     recheck triggers WhatsApp attempt → `unknown`.
  ///
  /// Falls back to `unknown` on any lookup error so the user still sees
  /// both prices and the dispatcher's default WhatsApp-first behaviour
  /// is reflected in the quote.
  static Future<MessageChannelExpectation> resolveExpectedChannel(
      String phoneNumber) async {
    try {
      if (!isValidSAPhoneNumber(phoneNumber)) {
        return MessageChannelExpectation.unknown;
      }
      final normalizedPhone = normalizePhoneNumber(phoneNumber);
      final querySnapshot = await FirebaseFirestore.instance
          .collection('successfulWhatsAppNumbers')
          .where('phoneNumber', isEqualTo: normalizedPhone)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        // Never checked → dispatcher will try WhatsApp first.
        return MessageChannelExpectation.unknown;
      }

      final data = querySnapshot.docs.first.data();
      final hasWhatsApp = data['hasWhatsApp'] as bool? ?? false;
      final lastChecked = (data['lastChecked'] as Timestamp?)?.toDate();
      final needsRecheck = lastChecked == null ||
          DateTime.now().difference(lastChecked).inDays > 30;

      if (hasWhatsApp) {
        return MessageChannelExpectation.whatsapp;
      }
      if (needsRecheck) {
        // Stale "no" → dispatcher retries WhatsApp.
        return MessageChannelExpectation.unknown;
      }
      return MessageChannelExpectation.sms;
    } catch (_) {
      // Any Firestore hiccup: degrade gracefully — show both prices,
      // bias to WhatsApp-first which matches dispatcher default.
      return MessageChannelExpectation.unknown;
    }
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
        // SMS-safe currency formatting in the substituted body. The
        // WhatsApp `amount` argument passed to `sendFormattedMessage`
        // below keeps the locale-formatted display form because the
        // WhatsApp template content is rendered server-side and not
        // subject to GSM-7/UCS-2 segmentation.
        message = SMSMessages.creditConfirmationShort
            .replaceAll('{customerName}', customerName)
            .replaceAll('{amount}', CurrencyUtil.formatForSms(amount));
        messageCost = pricingService.smsReminderTemplatePrice;
      } else {
        templateSid = payment_transaction;
        inAppNotification = InAppNotifications.paymentTransactionNotification;
        message = SMSMessages.paymentConfirmationShort
            .replaceAll('{customerName}', customerName)
            .replaceAll('{amount}', CurrencyUtil.formatForSms(amount));
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
          messageCost,
          message);
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'sendConfirmationMessage failed',
      );
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
          SMSMessages.onboardingShort,
          templateSid,
          mobileNumber,
          '0',
          InAppNotifications.onboardingSuccessNotification,
          pricingService.smsReminderTemplatePrice,
          SMSMessages.onboardingShort);
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'sendOnboardingMessage failed',
      );
    }
  }

  Future<void> sendReminderMessage(
    String currentUserId,
    String customerId,
    String customerName,
    double amount,
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
          CurrencyUtil.format(amount),
          InAppNotifications.paymentReminderNotification,
          pricingService.smsReminderTemplatePrice,
          SMSMessages.reminderShort);
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'sendReminderMessage failed',
      );
    }
  }
}
