import 'package:cloud_functions/cloud_functions.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/services/store_session.dart';

class MessagingPricingUnavailable implements Exception {
  const MessagingPricingUnavailable([
    this.message = 'Messaging pricing is temporarily unavailable.',
  ]) : code = 'unavailable';

  const MessagingPricingUnavailable.withCode(this.code, this.message);

  final String code;
  final String message;

  factory MessagingPricingUnavailable.fromError(Object error) {
    if (error is MessagingPricingUnavailable) return error;
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unauthenticated':
          return const MessagingPricingUnavailable.withCode('unauthenticated',
              'Sign in again to load current message prices.');
        case 'permission-denied':
          return const MessagingPricingUnavailable.withCode('permission-denied',
              'You do not have access to this shop’s message prices. Review the active shop and try again.');
        case 'failed-precondition':
          if (error.message == 'App verification is required.') {
            return const MessagingPricingUnavailable.withCode(
                'app-check-required',
                'This app could not be verified to load prices. Reopen it and try again. If this continues, contact support.');
          }
          return const MessagingPricingUnavailable.withCode(
              'failed-precondition',
              'Current message prices are not available yet. Try again later.');
        case 'not-found':
        case 'unimplemented':
          return const MessagingPricingUnavailable.withCode('not-found',
              'The message pricing service is unavailable. Try again later.');
        case 'deadline-exceeded':
        case 'unavailable':
          return const MessagingPricingUnavailable.withCode('unavailable',
              'Current message prices could not load. Check your connection and try again.');
      }
    }
    return const MessagingPricingUnavailable();
  }

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
      if (value is! num ||
          !value.isFinite ||
          value <= 0 ||
          value.toInt() != value) {
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
    final snapshot = await loadSnapshot(loader: loader);
    return DynamicPricingService(remoteConfigService, snapshot);
  }

  /// Reads the server-owned message rates independently of payment-fee config.
  /// Error codes remain safe to present; response details are never exposed.
  static Future<MessagingPricingSnapshotV1> loadSnapshot({
    MessagingPricingLoader? loader,
    String? storeId,
  }) async {
    try {
      final activeStore = storeId ?? StoreSession.instance.storeId;
      final data = loader == null
          ? Map<String, dynamic>.from(
              (await FirebaseFunctions.instance
                      .httpsCallable('getMessagingPricingV1')
                      .call(
                          {if (activeStore.isNotEmpty) 'storeId': activeStore}))
                  .data as Map,
            )
          : await loader(activeStore);
      return MessagingPricingSnapshotV1.fromMap(data);
    } catch (error) {
      throw MessagingPricingUnavailable.fromError(error);
    }
  }

  double get smsReminderTemplatePrice => snapshot.smsCustomerMinor / 100;
  double get smsPaymentTemplatePrice => snapshot.smsPaymentMinor / 100;
  double get whatsappUtilityPrice => snapshot.whatsappUtilityMinor / 100;
  double get whatsappPromotionPrice => snapshot.whatsappPromotionMinor / 100;
}
