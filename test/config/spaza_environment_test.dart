import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/config/firebase_environment.dart';
import 'package:pasella/config/spaza_environment.dart';
import 'package:pasella/services/environment_contract_service.dart';

void main() {
  const productionOptions = FirebaseOptions(
    apiKey: 'test-key',
    appId: 'test-app',
    messagingSenderId: '123',
    projectId: 'pasella-ledger',
  );

  group('SpazaRuntimeEnvironment', () {
    test('parses the three supported environments', () {
      expect(
        SpazaRuntimeEnvironment.parse('local'),
        SpazaEnvironment.local,
      );
      expect(
        SpazaRuntimeEnvironment.parse('development'),
        SpazaEnvironment.development,
      );
      expect(
        SpazaRuntimeEnvironment.parse('production'),
        SpazaEnvironment.production,
      );
    });

    test('rejects unknown environments', () {
      expect(
        () => SpazaRuntimeEnvironment.parse('staging'),
        throwsStateError,
      );
    });

    test('production only accepts the legacy production project', () {
      expect(
        () => SpazaRuntimeEnvironment.validateFirebaseProject(
          environment: SpazaEnvironment.production,
          projectId: 'spazaone-dev',
        ),
        throwsStateError,
      );
      expect(
        () => SpazaRuntimeEnvironment.validateFirebaseProject(
          environment: SpazaEnvironment.production,
          projectId: 'pasella-ledger',
        ),
        returnsNormally,
      );
    });

    test('development only accepts the named development projects', () {
      for (final projectId in ['spazaone-dev', 'spazaone-dev-za']) {
        expect(
          () => SpazaRuntimeEnvironment.validateFirebaseProject(
            environment: SpazaEnvironment.development,
            projectId: projectId,
          ),
          returnsNormally,
        );
      }
      expect(
        () => SpazaRuntimeEnvironment.validateFirebaseProject(
          environment: SpazaEnvironment.development,
          projectId: 'pasella-ledger',
        ),
        throwsStateError,
      );
    });

    test('local only accepts isolated demo projects', () {
      expect(
        () => SpazaRuntimeEnvironment.validateFirebaseProject(
          environment: SpazaEnvironment.local,
          projectId: 'demo-spazaone',
        ),
        returnsNormally,
      );
      expect(
        () => SpazaRuntimeEnvironment.validateFirebaseProject(
          environment: SpazaEnvironment.local,
          projectId: 'spazaone-dev',
        ),
        throwsStateError,
      );
    });
  });

  group('FirebaseEnvironment', () {
    test('uses flavor-selected native options on physical mobile builds', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(
          FirebaseEnvironment.shouldUseNativePlatformOptions(
            isWeb: false,
            platform: platform,
            emulatorMode: false,
          ),
          isTrue,
        );
      }
    });

    test('keeps explicit options for emulator, web, and desktop builds', () {
      expect(
        FirebaseEnvironment.shouldUseNativePlatformOptions(
          isWeb: false,
          platform: TargetPlatform.android,
          emulatorMode: true,
        ),
        isFalse,
      );
      expect(
        FirebaseEnvironment.shouldUseNativePlatformOptions(
          isWeb: true,
          platform: TargetPlatform.android,
          emulatorMode: false,
        ),
        isFalse,
      );
      expect(
        FirebaseEnvironment.shouldUseNativePlatformOptions(
          isWeb: false,
          platform: TargetPlatform.macOS,
          emulatorMode: false,
        ),
        isFalse,
      );
    });

    test('rejects emulator mode outside local builds', () {
      expect(
        () => FirebaseEnvironment.resolveOptions(
          productionOptions,
          emulatorMode: true,
          projectId: 'demo-spazaone',
          runtimeEnvironment: SpazaEnvironment.development,
        ),
        throwsStateError,
      );
    });

    test('uses an isolated demo project for local emulator builds', () {
      final options = FirebaseEnvironment.resolveOptions(
        productionOptions,
        emulatorMode: true,
        projectId: 'demo-spazaone',
        runtimeEnvironment: SpazaEnvironment.local,
      );
      expect(options.projectId, 'demo-spazaone');
    });

    test('rejects a production project in a development build', () {
      expect(
        () => FirebaseEnvironment.resolveOptions(
          productionOptions,
          emulatorMode: false,
          projectId: '',
          runtimeEnvironment: SpazaEnvironment.development,
        ),
        throwsStateError,
      );
    });
  });

  group('EnvironmentContractService', () {
    test('accepts an exact development app/backend match', () {
      expect(
        () => EnvironmentContractService.validate(
          expectedEnvironment: SpazaEnvironment.development,
          initializedProjectId: 'spazaone-dev',
          serverEnvironment: 'development',
          serverProjectId: 'spazaone-dev',
        ),
        returnsNormally,
      );
    });

    test('rejects a production backend for a development binary', () {
      expect(
        () => EnvironmentContractService.validate(
          expectedEnvironment: SpazaEnvironment.development,
          initializedProjectId: 'spazaone-dev',
          serverEnvironment: 'production',
          serverProjectId: 'pasella-ledger',
        ),
        throwsStateError,
      );
    });
  });
}
