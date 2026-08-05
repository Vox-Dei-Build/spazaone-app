import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/consent_service.dart';
import 'package:pasella/services/payment_receipt_tracker.dart';

void main() {
  late Directory hiveDirectory;
  late Box<dynamic> box;
  late ConsentState consent;
  late List<String> emitted;
  late PaymentReceiptTracker tracker;

  const payment = PaymentReceived(
    transactionId: 'cash_sale:sale-1',
    amountBucket: '50-200',
    source: 'cash_sale',
    method: 'cash',
  );

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'spaza-one-payment-receipt-test-',
    );
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<dynamic>('payment-receipt-test');
    consent = const ConsentState.firstRun().copyWith(
      analytics: true,
      decidedAt: DateTime.utc(2026, 8, 6),
    );
    emitted = <String>[];
    tracker = PaymentReceiptTracker(
      box: box,
      consentState: () => consent,
      emit: (event) async => emitted.add(event.transactionId),
    );
  });

  tearDown(() async {
    await box.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('hands a confirmed payment off once', () async {
    await tracker.capture(payment);
    await tracker.capture(payment);

    expect(emitted, ['cash_sale:sale-1']);
  });

  test('serializes concurrent callbacks for the same payment', () async {
    final firstEmissionStarted = Completer<void>();
    final releaseEmission = Completer<void>();
    tracker = PaymentReceiptTracker(
      box: box,
      consentState: () => consent,
      emit: (event) async {
        emitted.add(event.transactionId);
        firstEmissionStarted.complete();
        await releaseEmission.future;
      },
    );

    final first = tracker.capture(payment);
    await firstEmissionStarted.future;
    final duplicate = tracker.capture(payment);
    releaseEmission.complete();
    await Future.wait([first, duplicate]);

    expect(emitted, ['cash_sale:sale-1']);
  });

  test('does not backdate a payment after consent changes', () async {
    consent = const ConsentState.firstRun();
    await tracker.capture(payment);

    consent = consent.copyWith(
      analytics: true,
      decidedAt: DateTime.utc(2026, 8, 6),
    );
    await tracker.capture(payment);

    expect(emitted, isEmpty);
  });

  test('tracks different transaction IDs independently', () async {
    await tracker.capture(payment);
    await tracker.capture(
      const PaymentReceived(
        transactionId: 'ledger_payment:payment-2',
        amountBucket: '200-500',
        source: 'ledger_repayment',
        method: 'manual',
      ),
    );

    expect(emitted, ['cash_sale:sale-1', 'ledger_payment:payment-2']);
  });

  test('caps the persisted receipt set', () async {
    const resolutionsKey = 'measurement.payment_received.resolutions.v1';
    final recordedAt = DateTime.now().millisecondsSinceEpoch;
    await box.put(resolutionsKey, {
      for (var index = 0; index < 2048; index++)
        'cash_sale:existing-$index': recordedAt + index,
    });

    await tracker.capture(payment);

    final resolutions = Map<String, dynamic>.from(
      box.get(resolutionsKey) as Map,
    );
    expect(resolutions, hasLength(2048));
    expect(resolutions, contains('cash_sale:sale-1'));
  });
}
