import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/services/whatsapp_messaging_service.dart';
import 'package:pasella/utils/phone_util.dart';

class OrderStatusMessagingService {
  final Map<String, String> _templateIds;
  final DynamicPricingService _pricingService;
  final String _supportNumber;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Map<String, String> _messageTemplates = {
    'ACCEPT_BNPL':
        'BNPL approved 🎉\nHi {{customerName}}, your Pay Later request for order {{orderId}} is approved.\nTotal: {{amount}} · Items: {{itemsCount}}\nCollect at: {{pickupLocation}}. We’ll remind you until it’s settled.\nNeed help? {{support}}',
    'REJECT_BNPL':
        'BNPL decision\nHi {{customerName}}, your Pay Later request for order {{orderId}} wasn’t approved.\nYou can still pay cash {{amount}} and collect.\nQuestions? {{support}}',
    'MARK_CASH_RECEIVED':
        'Payment received ✅\nThanks {{customerName}}! We received {{amount}} for order {{orderId}} ({{itemsCount}} items).\nCollect at {{pickupLocation}}.\nKeep this for your records.',
    'MARK_COLLECTED':
        'Order collected 📦\nHi {{customerName}}, order {{orderId}} has been marked collected.\nThank you for shopping with us!\nWe appreciate you.',
    'SETTLE_BNPL':
        'BNPL settled ✅\nThanks {{customerName}}! Your Pay Later for order {{orderId}} is fully settled.\nFinal payment: {{amount}}.\nYou’re all squared up.',
    'CANCEL_ORDER':
        'Order cancelled\nHi {{customerName}}, order {{orderId}} has been cancelled.\nIf this was a mistake, reply and we’ll help.\nSupport: {{support}}',
  };

  OrderStatusMessagingService._(
      this._templateIds, this._pricingService, this._supportNumber);

  static Future<OrderStatusMessagingService> create() async {
    final rc = await RemoteConfigService.getInstance();
    final pricing = await DynamicPricingService.initialize();
    return OrderStatusMessagingService._({
      'ACCEPT_BNPL': rc.getString('TWILIO_ACCEPT_BNPL_TID'),
      'REJECT_BNPL': rc.getString('TWILIO_REJECT_BNPL_TID'),
      'MARK_CASH_RECEIVED': rc.getString('TWILIO_MARK_CASH_RECEIVED_TID'),
      'MARK_COLLECTED': rc.getString('TWILIO_MARK_COLLECTED_TID'),
      'SETTLE_BNPL': rc.getString('TWILIO_SETTLE_BNPL_TID'),
      'CANCEL_ORDER': rc.getString('TWILIO_CANCEL_ORDER_TID'),
    }, pricing, rc.getString('WA_SUPPORT_NUMBER'));
  }

  Future<void> sendStatusMessage({
    required String action,
    required String merchantId,
    required String customerId,
    required String customerName,
    required String orderId,
    String? amount,
    String? itemsCount,
    String? pickupLocation,
    String? support,
  }) async {
    final templateSid = _templateIds[action];
    if (templateSid == null || templateSid.isEmpty) return;

    final phoneNumber = await fetchAndFormatPhoneNumber(merchantId, customerId);
    if (phoneNumber == null || phoneNumber.isEmpty) return;

    final variables = <String, dynamic>{
      'customerName': customerName,
      'orderId': orderId,
    };
    if (amount != null) variables['amount'] = amount;
    if (itemsCount != null) variables['itemsCount'] = itemsCount;
    if (pickupLocation != null) variables['pickupLocation'] = pickupLocation;
    if (support != null) {
      variables['support'] = support;
    } else if (_supportNumber.isNotEmpty) {
      variables['support'] = _supportNumber;
    }

    final waService = await WhatsAppMessagingService.create();
    await waService.sendWhatsAppMessage(phoneNumber, templateSid, variables);

    final messageTemplate = _messageTemplates[action] ?? '';
    final message = _generateRenderedMessage(messageTemplate, variables);

    await _deductBalance(merchantId, _pricingService.whatsappUtilityPrice);
    await _storeNotification(
      merchantId: merchantId,
      customerId: customerId,
      message: message,
      phoneNumber: phoneNumber,
      variables: variables,
      templateSid: templateSid,
      messageCost: _pricingService.whatsappUtilityPrice,
    );
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
      String message, Map<String, dynamic> variables) {
    variables.forEach((key, value) {
      message = message.replaceAll('{{$key}}', value?.toString() ?? '');
    });
    return message;
  }

  Future<void> _storeNotification({
    required String merchantId,
    required String customerId,
    required String message,
    required String phoneNumber,
    required Map<String, dynamic> variables,
    required String templateSid,
    required double messageCost,
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
      'templateKey': templateSid,
      'templateType': 'whatsapp',
      'dateSent': Timestamp.now(),
    });
  }
}
