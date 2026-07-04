import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/crash_service.dart';

void main() {
  test('Remote Config platform failures are recoverable', () {
    final error = PlatformException(
      code: 'firebase_remote_config',
      message: 'Unable to connect to the server. Check your connection.',
    );

    expect(CrashService.instance.isRecoverableForTesting(error), isTrue);
  });
}
