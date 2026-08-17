/// Reports the merchant app version/build to Cloud Functions for gating.
/// Call after the merchant signs in (and again after app updates).
import 'dart:io' show Platform;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/config/build_provenance.dart';

class MerchantHeartbeat {
  MerchantHeartbeat._();
  static final MerchantHeartbeat instance = MerchantHeartbeat._();

  Future<void> send({
    required String merchantId,
  }) async {
    // Ensure signed in
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Heartbeat requires authenticated user.');
    }

    final info = await PackageInfo.fromPlatform();
    final appVersion = info.version; // e.g. "1.14.3"
    final build = int.tryParse(info.buildNumber) ?? 0;
    final platform = Platform.isAndroid ? 'android' : 'ios';

    final callable =
        FirebaseFunctions.instance.httpsCallable('heartbeatMerchantApp');

    // Optional: add a short timeout to avoid blocking UI too long
    final payload = <String, Object>{
      'merchantId': merchantId,
      'appVersion': appVersion,
      'buildNumber': build,
      'platform': platform,
      if (BuildProvenance.hasCommitSha)
        'commitSha': BuildProvenance.commitSha.toLowerCase(),
    };
    await callable.call(payload).timeout(const Duration(seconds: 8));
  }
}
