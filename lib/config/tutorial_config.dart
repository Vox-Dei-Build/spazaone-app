import 'package:firebase_remote_config/firebase_remote_config.dart';

class TutorialConfig {
  static final FirebaseRemoteConfig _remoteConfig =
      FirebaseRemoteConfig.instance;

  static String getTutorialUrl(String key) {
    return _remoteConfig.getString(key);
  }

  static const String TUTORIAL_CAPTURE_CUSTOMERS = 'TUTORIAL_CAPTURE_CUSTOMERS';
  static const String TUTORIAL_CAPTURE_SALES = 'TUTORIAL_CAPTURE_SALES';
  static const String TUTORIAL_CAPTURE_BNPL = 'TUTORIAL_CAPTURE_BNPL';
  static const String TUTORIAL_USE_PASELLA = 'TUTORIAL_USE_PASELLA';
  static const String TUTORIAL_WALLET = 'TUTORIAL_WALLET';
  static const String TUTORIAL_CAPTURE_STOCK = 'TUTORIAL_CAPTURE_STOCK';
  static const String TUTORIAL_RUN_PROMOTIONS = 'TUTORIAL_RUN_PROMOTIONS';
}
