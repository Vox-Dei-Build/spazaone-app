import 'package:cloud_functions/cloud_functions.dart';
import 'package:pasella/services/store_session.dart';

class MerchantOrderingOptions {
  const MerchantOrderingOptions({
    required this.configured,
    required this.payLaterEnabled,
    required this.deliveryEnabled,
    required this.deliveryFlatFeeMinor,
    required this.deliveryServiceAreaText,
  });

  const MerchantOrderingOptions.defaults()
      : configured = false,
        payLaterEnabled = false,
        deliveryEnabled = false,
        deliveryFlatFeeMinor = 0,
        deliveryServiceAreaText = '';

  final bool configured;
  final bool payLaterEnabled;
  final bool deliveryEnabled;
  final int deliveryFlatFeeMinor;
  final String deliveryServiceAreaText;

  factory MerchantOrderingOptions.fromMap(Map<String, dynamic> data) {
    final payLater = data['payLater'] is Map
        ? Map<String, dynamic>.from(data['payLater'] as Map)
        : const <String, dynamic>{};
    final delivery = data['delivery'] is Map
        ? Map<String, dynamic>.from(data['delivery'] as Map)
        : const <String, dynamic>{};
    return MerchantOrderingOptions(
      configured: data['configured'] == true,
      payLaterEnabled: payLater['enabled'] == true,
      deliveryEnabled: delivery['enabled'] == true,
      deliveryFlatFeeMinor: (delivery['flatFeeMinor'] as num?)?.toInt() ?? 0,
      deliveryServiceAreaText: delivery['serviceAreaText']?.toString() ?? '',
    );
  }
}

class MerchantOrderingOptionsService {
  MerchantOrderingOptionsService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<MerchantOrderingOptions> load() async {
    final result = await _functions
        .httpsCallable('getMerchantOrderingOptionsV1')
        .call({'storeId': StoreSession.instance.storeId});
    return MerchantOrderingOptions.fromMap(
      Map<String, dynamic>.from(result.data as Map? ?? const {}),
    );
  }

  Future<MerchantOrderingOptions> save({
    required bool payLaterEnabled,
    required bool deliveryEnabled,
    required int deliveryFlatFeeMinor,
    required String deliveryServiceAreaText,
  }) async {
    final result =
        await _functions.httpsCallable('updateMerchantOrderingOptionsV1').call({
      'storeId': StoreSession.instance.storeId,
      'payLater': {'enabled': payLaterEnabled},
      'delivery': {
        'enabled': deliveryEnabled,
        'flatFeeMinor': deliveryFlatFeeMinor,
        'serviceAreaText': deliveryServiceAreaText.trim(),
      },
    });
    return MerchantOrderingOptions.fromMap(
      Map<String, dynamic>.from(result.data as Map? ?? const {}),
    );
  }
}
