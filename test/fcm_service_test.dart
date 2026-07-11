import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/fcm_service.dart';

void main() {
  test('notification prompt is shown only before an OS permission decision',
      () {
    expect(
      FCMService.shouldPromptForPermission(AuthorizationStatus.notDetermined),
      isTrue,
    );
    expect(
      FCMService.shouldPromptForPermission(AuthorizationStatus.authorized),
      isFalse,
    );
    expect(
      FCMService.shouldPromptForPermission(AuthorizationStatus.provisional),
      isFalse,
    );
    expect(
      FCMService.shouldPromptForPermission(AuthorizationStatus.denied),
      isFalse,
    );
  });
}
