import 'package:flutter/material.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/config/firebase_environment.dart';
import 'package:pasella/services/fcm_service.dart';

class LedgerViewModel with ChangeNotifier {
  final FCMService _fcmService = FCMService();
  final searchTextNotifier = ValueNotifier<String?>(null);
  final hasCustomersNotifier = ValueNotifier<bool>(false);
  final AppModel dataModel;

  LedgerViewModel(this.dataModel);

  void initialize(BuildContext context) {
    setupFCM(context);
  }

  void setupFCM(BuildContext context) {
    if (FirebaseEnvironment.useEmulators) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        _fcmService.handleToken();
        _fcmService.listenToTokenRefresh(context);
      } catch (e) {
        print('An error occurred during FCM setup: $e');
      }
    });
  }

  @override
  void dispose() {
    searchTextNotifier.dispose();
    hasCustomersNotifier.dispose();
    super.dispose();
  }
}
