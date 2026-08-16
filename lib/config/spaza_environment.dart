/// Immutable build-time environment identity for every SpazaOne binary.
///
/// This value deliberately cannot be changed by Remote Config or a runtime
/// preference. A binary that is built for one environment must never be able
/// to connect to another environment's Firebase project.
enum SpazaEnvironment { local, development, production }

class SpazaRuntimeEnvironment {
  const SpazaRuntimeEnvironment._();

  static const String _compiledValue = String.fromEnvironment(
    'SPAZAONE_ENVIRONMENT',
    defaultValue: 'production',
  );

  static SpazaEnvironment get current => parse(_compiledValue);

  static bool get isProduction => current == SpazaEnvironment.production;
  static bool get isDevelopment => current == SpazaEnvironment.development;
  static bool get isLocal => current == SpazaEnvironment.local;

  static String get label => switch (current) {
        SpazaEnvironment.local => 'LOCAL',
        SpazaEnvironment.development => 'DEV',
        SpazaEnvironment.production => 'PRODUCTION',
      };

  static SpazaEnvironment parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'local' => SpazaEnvironment.local,
      'development' => SpazaEnvironment.development,
      'production' => SpazaEnvironment.production,
      _ => throw StateError(
          'Unknown SPAZAONE_ENVIRONMENT. Expected local, development, or '
          'production.',
        ),
    };
  }

  static void validateFirebaseProject({
    required SpazaEnvironment environment,
    required String projectId,
  }) {
    final normalized = projectId.trim();
    switch (environment) {
      case SpazaEnvironment.local:
        if (!normalized.startsWith('demo-')) {
          throw StateError(
            'A local SpazaOne build requires a demo-* Firebase project.',
          );
        }
      case SpazaEnvironment.development:
        if (normalized != 'spazaone-dev' && normalized != 'spazaone-dev-za') {
          throw StateError(
            'SpazaOne Development may only use spazaone-dev or '
            'spazaone-dev-za.',
          );
        }
      case SpazaEnvironment.production:
        if (normalized != 'pasella-ledger') {
          throw StateError(
            'A production SpazaOne build may only use pasella-ledger.',
          );
        }
    }
  }
}
