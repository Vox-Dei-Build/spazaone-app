import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:pasella/config/spaza_environment.dart';

/// Confirms that the initialized client and deployed Functions agree on the
/// same immutable environment before the app exposes any server-backed flow.
class EnvironmentContractService {
  const EnvironmentContractService._();

  static Future<void> verify() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('getEnvironmentInfo')
        .call<void>();
    final data = Map<String, dynamic>.from(result.data as Map);
    validate(
      expectedEnvironment: SpazaRuntimeEnvironment.current,
      initializedProjectId: Firebase.app().options.projectId,
      serverEnvironment: data['environment']?.toString() ?? '',
      serverProjectId: data['firebaseProjectId']?.toString() ?? '',
    );
  }

  @visibleForTesting
  static void validate({
    required SpazaEnvironment expectedEnvironment,
    required String initializedProjectId,
    required String serverEnvironment,
    required String serverProjectId,
  }) {
    final parsedServerEnvironment =
        SpazaRuntimeEnvironment.parse(serverEnvironment);
    if (parsedServerEnvironment != expectedEnvironment) {
      throw StateError(
        'SpazaOne app and backend environments do not match.',
      );
    }
    if (initializedProjectId.trim() != serverProjectId.trim()) {
      throw StateError(
        'SpazaOne app and backend Firebase projects do not match.',
      );
    }
    SpazaRuntimeEnvironment.validateFirebaseProject(
      environment: expectedEnvironment,
      projectId: serverProjectId,
    );
  }
}
