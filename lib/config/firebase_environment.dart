import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
    // Native Firebase auto-configures the default app from the bundled plist /
    // google-services file. Reuse that project namespace while routing every
    // mutable service to localhost; using a different default project name on
    // iOS causes the native SDK to reject a second [DEFAULT] app.
    defaultValue: 'pasella-ledger',
  );

  static FirebaseOptions options(FirebaseOptions production) {
    if (!useEmulators) return production;
    if (emulatorProjectId == production.projectId) return production;
    return FirebaseOptions(
      apiKey: production.apiKey,
      appId: production.appId,
      messagingSenderId: production.messagingSenderId,
      projectId: emulatorProjectId,
      authDomain: '$emulatorProjectId.firebaseapp.com',
      storageBucket: '$emulatorProjectId.appspot.com',
    );
  }

  static Future<void> connect() async {
    if (!useEmulators) return;
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
    FirebaseFunctions.instance.useFunctionsEmulator(emulatorHost, 5001);
    await FirebaseStorage.instance.useStorageEmulator(emulatorHost, 9199);
  }
}
