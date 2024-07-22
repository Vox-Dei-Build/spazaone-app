import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class RemoteConfigService {
  final FirebaseRemoteConfig _remoteConfig;

  RemoteConfigService._(this._remoteConfig) {
    if (!kIsWeb) {
      // Check if the platform is not web
      // Add real-time listener
      _remoteConfig.onConfigUpdated.listen((event) async {
        await _remoteConfig.activate();
        print("Remote config updated and activated.");
        // You can add more logic here if needed when the config updates.
      });
    }
  }

  static RemoteConfigService createInstance() {
    final remoteConfig = FirebaseRemoteConfig.instance;
    remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: Duration(seconds: 10),
      minimumFetchInterval: Duration(hours: 1),
    ));
    remoteConfig.setDefaults(<String, dynamic>{
      'TWILIO_ACCOUNT_SID': dotenv.env['TWILIO_ACCOUNT_SID']!,
      'TWILIO_AUTH_TOKEN': dotenv.env['TWILIO_AUTH_TOKEN']!,
      'TWILIO_NUMBER': dotenv.env['TWILIO_NUMBER']!,
      'SMARTLOOK_PROJECT_KEY': dotenv.env['SMARTLOOK_PROJECT_KEY']!,
    });
    return RemoteConfigService._(remoteConfig);
  }

  Future<void> initialize() async {
    try {
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      print("Failed to fetch and activate: $e");
    }
  }

  String? getString(String key) {
    return _remoteConfig.getString(key);
  }
}
