import 'package:pasella/config/remote_config.dart';
import 'package:pasella/services/whatsapp_messaging_service.dart';
import 'package:pasella/utils/phone_util.dart';

class OrderStatusMessagingService {
  final Map<String, String> _templateIds;

  OrderStatusMessagingService._(this._templateIds);

  static Future<OrderStatusMessagingService> create() async {
    final rc = await RemoteConfigService.getInstance();
    return OrderStatusMessagingService._({
      'ACCEPT_BNPL': rc.getString('TWILIO_ACCEPT_BNPL_TID'),
      'REJECT_BNPL': rc.getString('TWILIO_REJECT_BNPL_TID'),
      'MARK_CASH_RECEIVED': rc.getString('TWILIO_MARK_CASH_RECEIVED_TID'),
      'MARK_COLLECTED': rc.getString('TWILIO_MARK_COLLECTED_TID'),
      'SETTLE_BNPL': rc.getString('TWILIO_SETTLE_BNPL_TID'),
      'CANCEL_ORDER': rc.getString('TWILIO_CANCEL_ORDER_TID'),
    });
  }

  Future<void> sendStatusMessage({
    required String action,
    required String merchantId,
    required String customerId,
    required String customerName,
  }) async {
    final templateSid = _templateIds[action];
    if (templateSid == null || templateSid.isEmpty) return;

    final phoneNumber = await fetchAndFormatPhoneNumber(merchantId, customerId);
    if (phoneNumber == null || phoneNumber.isEmpty) return;

    final waService = await WhatsAppMessagingService.create();
    await waService.sendWhatsAppMessage(phoneNumber, templateSid, {
      'customerName': customerName,
    });
  }
}
