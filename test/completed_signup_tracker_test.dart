import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/services/completed_signup_tracker.dart';
import 'package:pasella/services/consent_service.dart';

void main() {
  late Directory hiveDirectory;
  late Box<dynamic> box;
  late ConsentState consent;
  late List<String> emitted;
  late CompletedSignupTracker tracker;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'pasella-completed-signup-test-',
    );
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<dynamic>('completed-signup-test');
    consent = const ConsentState.firstRun();
    emitted = <String>[];
    tracker = CompletedSignupTracker(
      box: box,
      consentState: () => consent,
      emit: ({required merchantId, required method}) async {
        emitted.add('$merchantId:$method');
      },
    );
  });

  tearDown(() async {
    await box.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('defers signup until analytics consent is granted', () async {
    await tracker.recordPhoneSignup(merchantId: 'merchant-1');
    expect(emitted, isEmpty);

    consent = const ConsentState.firstRun().copyWith(
      analytics: true,
      decidedAt: DateTime.utc(2026, 8, 5),
    );
    await tracker.resolveAfterConsent(merchantId: 'merchant-1');

    expect(emitted, ['merchant-1:phone']);
  });

  test('deduplicates repeated auth callbacks and dashboard resumes', () async {
    consent = const ConsentState.firstRun().copyWith(
      analytics: true,
      decidedAt: DateTime.utc(2026, 8, 5),
    );

    await tracker.recordPhoneSignup(merchantId: 'merchant-1');
    await tracker.recordPhoneSignup(merchantId: 'merchant-1');
    await tracker.resolveAfterConsent(merchantId: 'merchant-1');

    expect(emitted, ['merchant-1:phone']);
  });

  test('serializes concurrent auth callbacks', () async {
    consent = const ConsentState.firstRun().copyWith(
      analytics: true,
      decidedAt: DateTime.utc(2026, 8, 5),
    );
    final firstEmissionStarted = Completer<void>();
    final releaseEmission = Completer<void>();
    tracker = CompletedSignupTracker(
      box: box,
      consentState: () => consent,
      emit: ({required merchantId, required method}) async {
        emitted.add('$merchantId:$method');
        firstEmissionStarted.complete();
        await releaseEmission.future;
      },
    );

    final first = tracker.recordPhoneSignup(merchantId: 'merchant-1');
    await firstEmissionStarted.future;
    final duplicate = tracker.recordPhoneSignup(merchantId: 'merchant-1');
    releaseEmission.complete();
    await Future.wait([first, duplicate]);

    expect(emitted, ['merchant-1:phone']);
  });

  test('rejecting analytics discards rather than backdating signup', () async {
    await tracker.recordPhoneSignup(merchantId: 'merchant-1');

    consent = const ConsentState.firstRun().copyWith(
      analytics: false,
      decidedAt: DateTime.utc(2026, 8, 5),
    );
    await tracker.resolveAfterConsent(merchantId: 'merchant-1');

    consent = consent.copyWith(analytics: true);
    await tracker.recordPhoneSignup(merchantId: 'merchant-1');
    await tracker.resolveAfterConsent(merchantId: 'merchant-1');

    expect(emitted, isEmpty);
  });
}
