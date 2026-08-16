import 'package:cloud_functions/cloud_functions.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/services/store_session.dart';

class MessagingPricingUnavailable implements Exception {
  const MessagingPricingUnavailable([
    this.message = 'Messaging pricing is temporarily unavailable.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class MessagingPricingSnapshotV1 {
  const MessagingPricingSnapshotV1({
    required this.smsCustomerMinor,
    required this.smsPaymentMinor,
    required this.whatsappUtilityMinor,
    required this.whatsappPromotionMinor,
  });

  final int smsCustomerMinor;
  final int smsPaymentMinor;
  final int whatsappUtilityMinor;
  final int whatsappPromotionMinor;

  factory MessagingPricingSnapshotV1.fromMap(Map<String, dynamic> data) {
    int requiredMinor(String key) {
      final value = data[key];
      if (value is! num || value.toInt() <= 0) {
        throw const MessagingPricingUnavailable();
      }
      return value.toInt();
    }

    if (data['schemaVersion'] != 1 || data['currency'] != 'ZAR') {
      throw const MessagingPricingUnavailable();
    }
    return MessagingPricingSnapshotV1(
      smsCustomerMinor: requiredMinor('smsCustomerMinor'),
      smsPaymentMinor: requiredMinor('smsPaymentMinor'),
      whatsappUtilityMinor: requiredMinor('whatsappUtilityMinor'),
      whatsappPromotionMinor: requiredMinor('whatsappPromotionMinor'),
    );
  }
}

typedef MessagingPricingLoader = Future<Map<String, dynamic>> Function(
  String storeId,
);

/// Validated messaging prices supplied by the server billing authority.
///
/// Remote Config remains available for non-messaging presentation values, but
/// no paid send may derive an authoritative rate from a client-side default.
class DynamicPricingService {
  const DynamicPricingService(
    this.remoteConfigService,
    this.snapshot,
  );

  final RemoteConfigService remoteConfigService;
  final MessagingPricingSnapshotV1 snapshot;

  static Future<DynamicPricingService> initialize({
    MessagingPricingLoader? loader,
  }) async {
    final remoteConfigService = await RemoteConfigService.getInstance();
    try {
      final storeId = StoreSession.instance.storeId;
      final data = loader == null
          ? Map<String, dynamic>.from(
              (await FirebaseFunctions.instance
                      .httpsCallable('getMessagingPricingV1')
                      .call({if (storeId.isNotEmpty) 'storeId': storeId}))
                  .data as Map,
            )
          : await loader(storeId);
      return DynamicPricingService(
        remoteConfigService,
        MessagingPricingSnapshotV1.fromMap(data),
      );
    } on MessagingPricingUnavailable {
      rethrow;
    } catch (_) {
      throw const MessagingPricingUnavailable();
    }
  }

  double get smsReminderTemplatePrice => snapshot.smsCustomerMinor / 100;
  double get smsPaymentTemplatePrice => snapshot.smsPaymentMinor / 100;
  double get whatsappUtilityPrice => snapshot.whatsappUtilityMinor / 100;
  double get whatsappPromotionPrice => snapshot.whatsappPromotionMinor / 100;
}
