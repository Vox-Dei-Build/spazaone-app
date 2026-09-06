import 'dart:io';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/config/firebase_environment.dart';
import 'package:pasella/config/spaza_environment.dart';

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
      runtimeEnvironment: SpazaEnvironment.local,
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

  test('iOS notification permission stays out of unauthenticated startup', () {
    final mainDart = File('lib/main.dart').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(mainDart, contains('requestAlertPermission: false'));
    expect(mainDart, contains('requestSoundPermission: false'));
    expect(mainDart, contains('requestBadgePermission: false'));
    expect(
      appDelegate,
      isNot(contains('application.registerForRemoteNotifications()')),
    );
  });

  test('development and production Firebase app identities stay isolated', () {
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

    const productionIosAppId = '1:716158514645:ios:17eba128d70a92a7e5795c';
    final runtimeProject = environment['FIREBASE_ANDROID_PROJECT_ID'];
    expect(
      environment['FIREBASE_IOS_PROJECT_ID'],
      runtimeProject,
      reason: 'Android and iOS .env files must target the same lane.',
    );

    if (runtimeProject == 'spazaone-dev') {
      final developmentAndroid = jsonDecode(
        File('android/app/src/development/google-services.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final projectInfo =
          developmentAndroid['project_info'] as Map<String, dynamic>;
      final clients = developmentAndroid['client'] as List<dynamic>;
      final clientInfo = (clients.first as Map<String, dynamic>)['client_info']
          as Map<String, dynamic>;
      final androidClientInfo =
          clientInfo['android_client_info'] as Map<String, dynamic>;

      expect(
        environment['FIREBASE_ANDROID_APP_ID'],
        clientInfo['mobilesdk_app_id'],
        reason: 'Android .env app identity must match the registered app.',
      );
      expect(projectInfo['project_id'], 'spazaone-dev');
      expect(androidClientInfo['package_name'], 'com.tsepo.spazaone.dev');

      final developmentIosPlist = File(
        'ios/GoogleService-Info-development.plist',
      ).readAsStringSync();
      expect(
        developmentIosPlist,
        contains(environment['FIREBASE_IOS_APP_ID']),
        reason: 'iOS .env app identity must match the registered app.',
      );
      expect(developmentIosPlist, contains('spazaone-dev'));
      expect(developmentIosPlist, contains('com.tsepo.spazaone.dev'));
    } else {
      expect(runtimeProject, 'pasella-ledger');
      expect(environment['FIREBASE_IOS_APP_ID'], productionIosAppId);
    }

    final crashlytics = jsonDecode(
      File('ios/firebase_app_id_file.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(crashlytics['GOOGLE_APP_ID'], productionIosAppId);
    expect(crashlytics['FIREBASE_PROJECT_ID'], 'pasella-ledger');

    final productionIosPlist =
        File('ios/GoogleService-Info.plist').readAsStringSync();
    expect(productionIosPlist, contains(productionIosAppId));
    expect(productionIosPlist, contains('pasella-ledger'));
    expect(productionIosPlist, contains('com.tsepo.pasella'));
    expect(productionIosPlist, isNot(contains('spazaone-dev')));
  });

  test('iOS phone auth callback scheme follows the selected Firebase lane', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final xcodeProject =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    expect(infoPlist, contains(r'$(SPAZAONE_FIREBASE_URL_SCHEME)'));
    expect(
      xcodeProject,
      contains(
        'SPAZAONE_FIREBASE_URL_SCHEME = '
        '"app-1-317368517217-ios-b3e0537994e1b4a984a020";',
      ),
    );
    expect(
      xcodeProject,
      contains(
        'SPAZAONE_FIREBASE_URL_SCHEME = '
        '"app-1-716158514645-ios-17eba128d70a92a7e5795c";',
      ),
    );
  });
}
