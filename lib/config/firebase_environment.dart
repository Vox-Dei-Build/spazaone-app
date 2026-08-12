import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:pasella/config/spaza_environment.dart';

/// Compile-time Firebase isolation for local end-to-end QA.
///
/// No runtime or Remote Config value can redirect a production binary. The
/// emulator switch must be compiled into the build with `--dart-define`.
class FirebaseEnvironment {
  const FirebaseEnvironment._();

  static const bool useEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: false,
  );
  static const String emulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static const String emulatorProjectId = String.fromEnvironment(
    'FIREBASE_EMULATOR_PROJECT_ID',
    defaultValue: '',
  );

  static FirebaseOptions options(FirebaseOptions production) {
    return resolveOptions(
      production,
      emulatorMode: useEmulators,
      projectId: emulatorProjectId,
    );
  }

  @visibleForTesting
  static FirebaseOptions resolveOptions(
    FirebaseOptions production, {
    required bool emulatorMode,
    required String projectId,
    SpazaEnvironment? runtimeEnvironment,
  }) {
    final environment = runtimeEnvironment ?? SpazaRuntimeEnvironment.current;
    if (!emulatorMode) {
      SpazaRuntimeEnvironment.validateFirebaseProject(
        environment: environment,
        projectId: production.projectId,
      );
      return production;
    }
    if (environment != SpazaEnvironment.local) {
      throw StateError(
        'Firebase emulators require SPAZAONE_ENVIRONMENT=local.',
      );
    }
    final normalizedProjectId = projectId.trim();
    validateEmulatorConfiguration(
      projectId: normalizedProjectId,
      host: emulatorHost,
    );
    return FirebaseOptions(
      apiKey: production.apiKey,
      appId: production.appId,
      messagingSenderId: production.messagingSenderId,
      projectId: normalizedProjectId,
      authDomain: '$normalizedProjectId.firebaseapp.com',
      storageBucket: '$normalizedProjectId.appspot.com',
    );
  }

  @visibleForTesting
  static void validateEmulatorConfiguration({
    required String projectId,
    required String host,
  }) {
    final normalizedProject = projectId.trim();
    if (!normalizedProject.startsWith('demo-')) {
      throw StateError(
        'Emulator QA requires an explicit demo-* Firebase project id.',
      );
    }
    const localHosts = {'127.0.0.1', 'localhost', '10.0.2.2', '::1'};
    if (!localHosts.contains(host.trim())) {
      throw StateError(
        'Emulator QA requires a loopback Firebase emulator host.',
      );
    }
  }

  static Future<void> connect() async {
    final initializedProjectId = Firebase.app().options.projectId;
    SpazaRuntimeEnvironment.validateFirebaseProject(
      environment: SpazaRuntimeEnvironment.current,
      projectId: initializedProjectId,
    );
    if (!useEmulators) return;
    validateEmulatorConfiguration(
      projectId: emulatorProjectId,
      host: emulatorHost,
    );
    validateInitializedProject(
      expectedProjectId: emulatorProjectId,
      actualProjectId: initializedProjectId,
    );
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
    FirebaseFunctions.instance.useFunctionsEmulator(emulatorHost, 5001);
    await FirebaseStorage.instance.useStorageEmulator(emulatorHost, 9199);
  }

  @visibleForTesting
  static void validateInitializedProject({
    required String expectedProjectId,
    required String actualProjectId,
  }) {
    if (expectedProjectId.trim() != actualProjectId.trim()) {
      throw StateError(
        'Emulator QA Firebase app was initialized with the wrong project.',
      );
    }
  }
}
