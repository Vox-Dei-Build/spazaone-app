import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/fcm_service.dart';

class _UndecidedSettings extends Fake implements NotificationSettings {
  @override
  AuthorizationStatus get authorizationStatus =>
      AuthorizationStatus.notDetermined;
}

class _DelayedPermissionService extends FCMService {
  final result = Completer<NotificationSettings>();
  int explanations = 0;
  @override
  Future<NotificationSettings> getNotificationSettings() => result.future;
  @override
  Future<void> showPermissionExplanationDialog(BuildContext context,
      {bool Function()? shouldContinue}) async {
    explanations++;
  }
}

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

  test('messaging is disabled only for production-isolated emulator QA', () {
    expect(FCMService.messagingEnabled(emulatorMode: true), isFalse);
    expect(FCMService.messagingEnabled(emulatorMode: false), isTrue);
  });

  testWidgets(
      'late permission lookup cannot open over a changed login or store',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: Text('Home'))));
    final context = tester.element(find.text('Home'));
    final service = _DelayedPermissionService();
    var currentSession = true;
    final pending = service.requestPermissionIfNeeded(context,
        shouldContinue: () => currentSession);
    currentSession = false;
    service.result.complete(_UndecidedSettings());
    await pending;
    expect(service.explanations, 0);
  });

  testWidgets(
      'current completed startup still receives its permission explanation',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: Text('Home'))));
    final context = tester.element(find.text('Home'));
    final service = _DelayedPermissionService();
    final pending =
        service.requestPermissionIfNeeded(context, shouldContinue: () => true);
    service.result.complete(_UndecidedSettings());
    await pending;
    expect(service.explanations, 1);
  });
}
