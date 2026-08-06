import 'dart:io';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/config/firebase_environment.dart';

void main() {
  const production = FirebaseOptions(
    apiKey: 'production-api-key-placeholder',
    appId: 'production-app-id-placeholder',
    messagingSenderId: 'production-sender-placeholder',
    projectId: 'pasella-ledger',
    storageBucket: 'pasella-ledger.appspot.com',
  );

  test('production options are unchanged when emulator mode is off', () {
    final resolved = FirebaseEnvironment.resolveOptions(
      production,
      emulatorMode: false,
      projectId: '',
    );

    expect(resolved, same(production));
  });

  test('emulator options use only an explicit demo project namespace', () {
    final resolved = FirebaseEnvironment.resolveOptions(
      production,
      emulatorMode: true,
      projectId: 'demo-spazaone-qa',
    );

    expect(resolved.projectId, 'demo-spazaone-qa');
    expect(resolved.authDomain, 'demo-spazaone-qa.firebaseapp.com');
    expect(resolved.storageBucket, 'demo-spazaone-qa.appspot.com');
    expect(resolved.apiKey, production.apiKey);
    expect(resolved.appId, production.appId);
  });

  test('emulator configuration refuses production and remote targets', () {
    expect(
      () => FirebaseEnvironment.validateEmulatorConfiguration(
        projectId: 'pasella-ledger',
        host: '127.0.0.1',
      ),
      throwsStateError,
    );
    expect(
      () => FirebaseEnvironment.validateEmulatorConfiguration(
        projectId: 'demo-spazaone-qa',
        host: 'firebase.example.com',
      ),
      throwsStateError,
    );
  });

  test('emulator connection refuses an initialized production app', () {
    expect(
      () => FirebaseEnvironment.validateInitializedProject(
        expectedProjectId: 'demo-spazaone-qa',
        actualProjectId: 'pasella-ledger',
      ),
      throwsStateError,
    );
    expect(
      () => FirebaseEnvironment.validateInitializedProject(
        expectedProjectId: 'demo-spazaone-qa',
        actualProjectId: 'demo-spazaone-qa',
      ),
      returnsNormally,
    );
  });

  test('Firebase native auto-init is conditional only in debug builds', () {
    final debugManifest =
        File('android/app/src/debug/AndroidManifest.xml').readAsStringSync();
    final productionManifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final mainDart = File('lib/main.dart').readAsStringSync();

    expect(debugManifest, contains('FirebaseInitProvider'));
    expect(debugManifest, isNot(contains('tools:node="remove"')));
    expect(debugManifest, contains(r'${firebaseInitProviderEnabled}'));
    expect(
      debugManifest,
      contains('firebase_messaging_auto_init_enabled'),
    );
    expect(debugManifest, contains(r'${firebaseMessagingAutoInitEnabled}'));
    expect(debugManifest, contains(r'${firebaseEmulatorCleartextEnabled}'));
    expect(
      mainDart,
      isNot(contains('FirebaseMessaging.instance.setAutoInitEnabled(false)')),
      reason: 'Touching Firebase Messaging in emulator mode starts FIS.',
    );
    expect(productionManifest, isNot(contains('tools:node="remove"')));
    expect(productionManifest, isNot(contains('FirebaseInitProvider')));
  });

  test('tracked and runtime Firebase app identities stay aligned', () {
    final environment = <String, String>{};
    for (final rawLine in File('.env').readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
        continue;
      }
      final separator = line.indexOf('=');
      environment[line.substring(0, separator).trim()] =
          line.substring(separator + 1).trim().replaceAll(
                RegExp(r'''^['"]|['"]$'''),
                '',
              );
    }

    const androidAppId = '1:716158514645:android:a4f2b4756aafcebbe5795c';
    const iosAppId = '1:716158514645:ios:17eba128d70a92a7e5795c';
    expect(
      environment['FIREBASE_ANDROID_APP_ID'] == androidAppId,
      isTrue,
      reason: 'Android .env app identity must match the registered app.',
    );
    expect(
      environment['FIREBASE_IOS_APP_ID'] == iosAppId,
      isTrue,
      reason: 'iOS .env app identity must match the registered app.',
    );

    final crashlytics = jsonDecode(
      File('ios/firebase_app_id_file.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(crashlytics['GOOGLE_APP_ID'], iosAppId);
    expect(crashlytics['FIREBASE_PROJECT_ID'], 'pasella-ledger');

    final iosPlist = File('ios/GoogleService-Info.plist').readAsStringSync();
    expect(iosPlist, contains(iosAppId));
    expect(iosPlist, contains('com.tsepo.pasella'));
  });
}
