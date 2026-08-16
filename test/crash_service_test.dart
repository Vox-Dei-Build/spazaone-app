import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

  test('RenderFlex overflow is recorded as non-fatal', () {
    final details = FlutterErrorDetails(
      exception: FlutterError('A RenderFlex overflowed by 42 pixels.'),
      library: 'rendering library',
      context: ErrorDescription('during layout'),
    );

    expect(
      CrashService.instance.isNonFatalFlutterErrorForTesting(details),
      isTrue,
    );
  });

  test('layout diagnostics use coarse non-PII buckets', () {
    expect(
      CrashService.viewportSizeBucketForTesting(const Size(320, 568)),
      'compact',
    );
    expect(
      CrashService.viewportSizeBucketForTesting(const Size(412, 915)),
      'phone',
    );
    expect(CrashService.textScaleBucketForTesting(1), 'default');
    expect(CrashService.textScaleBucketForTesting(2), 'large');
  });

  test('route diagnostics strip queries and dynamic identifiers', () {
    expect(
      CrashService.sanitizeSurfaceForTesting(
        '/orders/customer-123?phone=27820000000',
      ),
      '/orders/:dynamic',
    );
    expect(CrashService.sanitizeSurfaceForTesting(null), 'unnamed');
  });
}
