import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/services/whatsapp_messaging_service.dart';
import 'package:pasella/utils/phone_util.dart';

/// Outcome of attempting to notify a customer about an order state
/// change. The previous implementation returned `Future<void>` which
/// meant the caller had no way to distinguish "WhatsApp sent and wallet
/// debited" from "no number on file, nothing happened" from "Twilio
/// failed silently". PAS-UX-07 makes this state explicit because the
/// merchant's wallet is being charged on the `sent` branch and they
/// deserve to see that as a discrete event.
enum OrderNotificationStatus {
  /// WhatsApp template was accepted by Twilio AND the wallet was
  /// debited by `whatsappUtilityPrice`.
  sent,

  /// No notification was attempted because the action has no template
  /// configured for this merchant (Remote Config gap).
  skippedNoTemplate,

  /// Customer has no usable phone number on record. Wallet was NOT
  /// charged.
  skippedNoPhone,

  /// Twilio call threw. Wallet was NOT charged. Caller should let the
  /// merchant retry.
  failed,
}

class OrderNotificationResult {
  const OrderNotificationResult({
    required this.status,
    this.cost = 0,
    this.errorMessage,
  });

  final OrderNotificationStatus status;

  /// ZAR cost actually debited from the merchant wallet. Zero on every
  /// non-`sent` branch — surface this in the snackbar so the merchant
  /// can reconcile the wallet movement against this action.
  final double cost;

  final String? errorMessage;

  bool get wasSent => status == OrderNotificationStatus.sent;
}

class OrderStatusMessagingService {
  final Map<String, String> _templateIds;
  final DynamicPricingService _pricingService;
  final String _supportNumber;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Map<String, String> _messageTemplates = {
    'ACCEPT_ORDER':
        'Order status update: your order {{1}} is now being prepared. Total due: {{2}}. {{3}}. Reply here if you need help.',
    'REJECT_ORDER':
        'Order update: the shop could not accept your order. Reference: {{1}}. Reason: {{2}}. Reply here and the shop can help adjust it.',
    'ASSIGN_DRIVER':
        'Delivery update: a driver has been assigned to your order. Reference: {{1}}. Driver: {{2}}. Phone: {{3}}. Please keep your phone nearby.',
    'MARK_OUT_FOR_DELIVERY':
        'On the way 🚗 Your order {{1}} is out for delivery. Driver: {{2}}. Phone: {{3}}. Please keep your phone nearby.',
    'MARK_DELIVERED':
        'Delivered ✅\nHi {{customerName}}, order {{orderId}} has been delivered.\nThank you for shopping with us!',
    'ACCEPT_BNPL':
        'BNPL approved 🎉\nHi {{customerName}}, your Pay Later request for order {{orderId}} is approved.\nTotal: {{amount}} · Items: {{itemsCount}}\nCollect at: {{pickupLocation}}. We’ll remind you until it’s settled.\nNeed help? {{support}}',
    'REJECT_BNPL':
        'BNPL decision\nHi {{customerName}}, your Pay Later request for order {{orderId}} wasn’t approved.\nYou can still pay cash {{amount}} and collect.\nQuestions? {{support}}',
    'MARK_CASH_RECEIVED':
        'Payment received ✅\nThanks {{customerName}}! We received {{amount}} for order {{orderId}} ({{itemsCount}} items).\n{{pickupLocation}}\nKeep this for your records.',
    'MARK_COLLECTED':
        'Order collected 📦\nHi {{customerName}}, order {{orderId}} has been marked collected.\nThank you for shopping with us!\nWe appreciate you.',
    'SETTLE_BNPL':
        'BNPL settled ✅\nThanks {{customerName}}! Your Pay Later for order {{orderId}} is fully settled.\nFinal payment: {{amount}}.\nYou’re all squared up.',
    'CANCEL_ORDER':
        'Order cancelled\nHi {{customerName}}, order {{orderId}} has been cancelled.\nIf this was a mistake, reply and we’ll help.\nSupport: {{support}}',
  };

  OrderStatusMessagingService._(
    this._templateIds,
    this._pricingService,
    this._supportNumber,
  );

  static Future<OrderStatusMessagingService> create() async {
    final rc = await RemoteConfigService.getInstance();
    final pricing = await DynamicPricingService.initialize();
    return OrderStatusMessagingService._(
      {
        'ACCEPT_ORDER': rc.getString('TWILIO_ACCEPT_ORDER_TID'),
        'REJECT_ORDER': rc.getString('TWILIO_REJECT_ORDER_TID'),
        'ASSIGN_DRIVER': rc.getString('TWILIO_ASSIGN_DRIVER_TID'),
        // The two new dispatch templates fall back to the existing
        // ASSIGN_DRIVER template SID when their dedicated key is not
        // configured. This keeps an operationally usable signal going
        // out (driver + phone + reference) the moment merchants tap
        // these actions, even before product rolls a separate template
        // through Twilio approval.
        'MARK_OUT_FOR_DELIVERY':
            rc.getString('TWILIO_MARK_OUT_FOR_DELIVERY_TID').isNotEmpty
                ? rc.getString('TWILIO_MARK_OUT_FOR_DELIVERY_TID')
                : rc.getString('TWILIO_ASSIGN_DRIVER_TID'),
        'MARK_DELIVERED':
            rc.getString('TWILIO_MARK_DELIVERED_TID').isNotEmpty
                ? rc.getString('TWILIO_MARK_DELIVERED_TID')
                : rc.getString('TWILIO_MARK_COLLECTED_TID'),
        'ACCEPT_BNPL': rc.getString('TWILIO_ACCEPT_BNPL_TID'),
        'REJECT_BNPL': rc.getString('TWILIO_REJECT_BNPL_TID'),
        'MARK_CASH_RECEIVED': rc.getString('TWILIO_MARK_CASH_RECEIVED_TID'),
        'MARK_COLLECTED': rc.getString('TWILIO_MARK_COLLECTED_TID'),
        'SETTLE_BNPL': rc.getString('TWILIO_SETTLE_BNPL_TID'),
        'CANCEL_ORDER': rc.getString('TWILIO_CANCEL_ORDER_TID'),
      },
      pricing,
      rc.getString('WA_SUPPORT_NUMBER'),
    );
  }

  Future<OrderNotificationResult> sendStatusMessage({
    required String action,
    required String merchantId,
    required String customerId,
    required String customerName,
    required String orderId,
    String? amount,
    String? itemsCount,
    String? pickupLocation,
    String? driverName,
    String? driverPhone,
    String? rejectionReason,
    String? support,
  }) async {
    final templateSid = _templateIds[action];
    if (templateSid == null || templateSid.isEmpty) {
      return const OrderNotificationResult(
        status: OrderNotificationStatus.skippedNoTemplate,
      );
    }

    final phoneNumber = await fetchAndFormatPhoneNumber(merchantId, customerId);
    if (phoneNumber == null || phoneNumber.isEmpty) {
      await _stampOrderMessage(
        merchantId: merchantId,
        orderId: orderId,
        data: {
          'channel': 'whatsapp',
          'status': 'unsent',
          'reason': 'no_phone_number',
          'action': action,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      return const OrderNotificationResult(
        status: OrderNotificationStatus.skippedNoPhone,
      );
    }

    final variables = _variablesForAction(
      action: action,
      customerName: customerName,
      orderId: orderId,
      amount: amount,
      itemsCount: itemsCount,
      pickupLocation: pickupLocation,
      driverName: driverName,
      driverPhone: driverPhone,
      rejectionReason: rejectionReason,
    );
    if (support != null) {
      variables['support'] = support;
    } else if (_supportNumber.isNotEmpty) {
      variables['support'] = _supportNumber;
    }

    try {
      await _stampOrderMessage(
        merchantId: merchantId,
        orderId: orderId,
        data: {
          'channel': 'whatsapp',
          'status': 'queued',
          'action': action,
          'templateKey': templateSid,
          'queuedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      final waService = await WhatsAppMessagingService.create();
      final messageId = await waService.sendWhatsAppMessage(
        phoneNumber,
        templateSid,
        variables,
      );
      if (messageId == null) {
        await _stampOrderMessage(
          merchantId: merchantId,
          orderId: orderId,
          data: {
            'channel': 'whatsapp',
            'status': 'failed',
            'reason': 'twilio_rejected',
            'action': action,
            'failedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        return const OrderNotificationResult(
          status: OrderNotificationStatus.failed,
          errorMessage: 'WhatsApp send was not accepted by Twilio.',
        );
      }

      final messageTemplate = _messageTemplates[action] ?? '';
      final message = _generateRenderedMessage(messageTemplate, variables);

      await _stampOrderMessage(
        merchantId: merchantId,
        orderId: orderId,
        data: {
          'channel': 'whatsapp',
          'status': 'sent',
          'sid': messageId,
          'action': action,
          'templateKey': templateSid,
          'sentAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      final cost = _pricingService.whatsappUtilityPrice;
      await _deductBalance(merchantId, cost);
      await _storeNotification(
        merchantId: merchantId,
        customerId: customerId,
        orderId: orderId,
        message: message,
        phoneNumber: phoneNumber,
        variables: variables,
        templateSid: templateSid,
        messageCost: cost,
        messageSid: messageId,
      );
      // ignore: unawaited_futures
      _pollAndStampDelivery(
        merchantId: merchantId,
        orderId: orderId,
        messageSid: messageId,
        waService: waService,
      );
      return OrderNotificationResult(
        status: OrderNotificationStatus.sent,
        cost: cost,
      );
    } catch (e) {
      return OrderNotificationResult(
        status: OrderNotificationStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _pollAndStampDelivery({
    required String merchantId,
    required String orderId,
    required String messageSid,
    required WhatsAppMessagingService waService,
  }) async {
    try {
      final delivered = await waService.pollMessageStatus(messageSid);
      await _stampOrderMessage(
        merchantId: merchantId,
        orderId: orderId,
        data: {
          'status': delivered ? 'delivered' : 'failed',
          if (delivered) 'deliveredAt': FieldValue.serverTimestamp(),
          if (!delivered) 'failedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    } catch (_) {
      // Best-effort only. The prior state remains visible on the order.
    }
  }

  Future<void> _stampOrderMessage({
    required String merchantId,
    required String orderId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final orderRef = _firestore
          .collection('users')
          .doc(merchantId)
          .collection('sales')
          .doc(orderId);

      final namespaced = <String, dynamic>{
        for (final e in data.entries) 'lastMessage.${e.key}': e.value,
      };
      await orderRef.set({}, SetOptions(merge: true));
      await orderRef.update(namespaced);
    } catch (_) {
      // Visibility is best-effort and must not break the order action.
    }
  }

  Future<void> _deductBalance(String merchantId, double cost) async {
    final walletRef = _firestore
        .collection('users')
        .doc(merchantId)
        .collection('wallet')
        .doc('current');

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(walletRef);
      if (!snapshot.exists) return;

      final currentBalance = (snapshot['virtualBalance'] ?? 0).toDouble();
      final newBalance = currentBalance - cost;

      transaction.update(walletRef, {'virtualBalance': newBalance});
    });
  }

  String _generateRenderedMessage(
    String message,
    Map<String, dynamic> variables,
  ) {
    variables.forEach((key, value) {
      message = message.replaceAll('{{$key}}', value?.toString() ?? '');
    });
    return message;
  }

  Map<String, dynamic> _variablesForAction({
    required String action,
    required String customerName,
    required String orderId,
    String? amount,
    String? itemsCount,
    String? pickupLocation,
    String? driverName,
    String? driverPhone,
    String? rejectionReason,
  }) {
    if (action == 'ACCEPT_ORDER') {
      return {
        '1': orderId,
        '2': amount ?? 'the order total',
        '3': pickupLocation ?? 'The shop will confirm collection or delivery.',
      };
    }
    if (action == 'REJECT_ORDER') {
      return {
        '1': orderId,
        '2': rejectionReason ?? 'Unavailable right now',
      };
    }
    if (action == 'ASSIGN_DRIVER' || action == 'MARK_OUT_FOR_DELIVERY') {
      return {
        '1': orderId,
        '2': (driverName ?? '').isNotEmpty ? driverName : 'the shop driver',
        '3': (driverPhone ?? '').isNotEmpty ? driverPhone : 'the shop',
      };
    }
    final variables = <String, dynamic>{
      'customerName': customerName,
      'orderId': orderId,
    };
    if (amount != null) variables['amount'] = amount;
    if (itemsCount != null) variables['itemsCount'] = itemsCount;
    if (pickupLocation != null) variables['pickupLocation'] = pickupLocation;
    return variables;
  }

  Future<void> _storeNotification({
    required String merchantId,
    required String customerId,
    required String orderId,
    required String message,
    required String phoneNumber,
    required Map<String, dynamic> variables,
    required String templateSid,
    required double messageCost,
    String? messageSid,
  }) async {
    final notificationRef = _firestore
        .collection('notifications')
        .doc(merchantId)
        .collection('customer_notifications');

    await notificationRef.add({
      'timestamp': FieldValue.serverTimestamp(),
      'message': message,
      'messageCost': messageCost,
      'merchant': merchantId,
      'customer_details': variables,
      'customer_phone': phoneNumber,
      'customer_id': customerId,
      'orderId': orderId,
      if (messageSid != null) 'twilioSid': messageSid,
      'templateKey': templateSid,
      'templateType': 'whatsapp',
      'dateSent': Timestamp.now(),
    });
  }
}
