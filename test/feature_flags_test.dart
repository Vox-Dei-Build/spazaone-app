import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/utils/feature_flags.dart';

class _FakeRemoteConfig implements RemoteConfigBoolReader {
  _FakeRemoteConfig(this.values);

  final Map<String, bool> values;

  @override
  bool getBool(String key, {bool defaultValue = false}) {
    return values[key] ?? defaultValue;
  }
}

void main() {
  tearDown(() {
    FeatureFlags.applyFlagsForTesting(_FakeRemoteConfig(const {}));
  });

  test('multi-store notifier follows activated feature flag values', () {
    final reader = _FakeRemoteConfig({
      'FEATURE_MULTI_STORE_OPERATORS_ENABLED': true,
    });

    FeatureFlags.applyFlagsForTesting(reader);

    expect(FeatureFlags.enableMultiStoreOperators, isTrue);
    expect(FeatureFlags.multiStoreOperatorsEnabled.value, isTrue);

    reader.values['FEATURE_MULTI_STORE_OPERATORS_ENABLED'] = false;
    FeatureFlags.applyFlagsForTesting(reader);

    expect(FeatureFlags.enableMultiStoreOperators, isFalse);
    expect(FeatureFlags.multiStoreOperatorsEnabled.value, isFalse);
  });
}
