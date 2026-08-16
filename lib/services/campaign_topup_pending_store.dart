import 'package:hive_local_storage/hive_local_storage.dart';

/// Keeps only the opaque, non-secret intent identifier needed to resume a
/// webhook-backed campaign balance check after an app restart.
class CampaignTopupPendingStore {
  const CampaignTopupPendingStore._();

  static const _keyPrefix = 'payments.campaign_topup.pending.v1';

  static String _key(String merchantId) => '$_keyPrefix:$merchantId';

  static String? read(String merchantId) {
    if (merchantId.trim().isEmpty) return null;
    final value = Hive.box('appBox').get(_key(merchantId));
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static Future<void> save(String merchantId, String intentId) async {
    if (merchantId.trim().isEmpty || intentId.trim().isEmpty) return;
    await Hive.box('appBox').put(_key(merchantId), intentId.trim());
  }

  static Future<void> clear(String merchantId) async {
    if (merchantId.trim().isEmpty) return;
    await Hive.box('appBox').delete(_key(merchantId));
  }
}
