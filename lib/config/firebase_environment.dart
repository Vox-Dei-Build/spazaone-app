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

  /// Development packages are commonly installed directly on test devices,
  /// including release-mode builds used to check production optimisations.
  /// Those installs cannot satisfy Play Integrity or App Attest distribution
  /// checks, so the development Firebase apps use their registered debug
  /// tokens. Production keeps the platform attestation providers in release
  /// mode, while ordinary debug builds preserve the existing debug-provider
  /// behaviour.
  static bool shouldUseDebugAppCheckProviders({
    bool? debugMode,
    SpazaEnvironment? runtimeEnvironment,
  }) {
    final isDebugBuild = debugMode ?? kDebugMode;
    final environment = runtimeEnvironment ?? SpazaRuntimeEnvironment.current;
    return isDebugBuild || environment == SpazaEnvironment.development;
  }

  /// Mobile flavors carry their Firebase identity in the native Android and
  /// iOS configuration selected by Gradle/Xcode. Using the `.env`-backed
  /// generated options on those platforms would bypass that flavor selection
  /// and can pair a development package with the production Firebase app.
  static bool shouldUseNativePlatformOptions({
    required bool isWeb,
    required TargetPlatform platform,
    bool? emulatorMode,
  }) {
    final usesEmulators = emulatorMode ?? useEmulators;
    return !usesEmulators &&
        !isWeb &&
        (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
  }

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
