import 'package:firebase_core/firebase_core.dart';
import 'package:pasella/config/firebase_environment.dart';

/// Builds Cloud Functions URLs from the Firebase app actually loaded on the
/// device. A staging build can therefore never call production merely because
/// an endpoint was hard-coded in an older service.
class FunctionEndpoints {
  const FunctionEndpoints._();

  static Uri https(String functionName, {String region = 'us-central1'}) {
    final projectId = Firebase.app().options.projectId.trim();
    if (projectId.isEmpty) {
      throw StateError('Firebase project id is unavailable.');
    }
    if (FirebaseEnvironment.useEmulators) {
      return Uri.http(
        '${FirebaseEnvironment.emulatorHost}:5001',
        '/$projectId/$region/$functionName',
      );
    }
    return Uri.https(
      '$region-$projectId.cloudfunctions.net',
      functionName,
    );
  }
}
