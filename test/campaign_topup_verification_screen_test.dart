import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/widgets/campaign_topup_verification_screen.dart';
import 'package:pasella/services/paystack_service.dart';

CampaignTopupStatusResult result(CampaignTopupStatus status) =>
    CampaignTopupStatusResult(
      status: status,
      creditAmountMinor: 1000,
      totalChargeMinor: 1025,
      updatedAtMs: 1,
    );

void main() {
  testWidgets('never celebrates a checking payment', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CampaignTopupVerificationScreen(
          statusReader: () async => result(CampaignTopupStatus.checking),
          pollDelays: const [Duration.zero],
          successDelay: Duration.zero,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topup-paid')), findsNothing);
    expect(find.text('Money added'), findsNothing);
  });

  testWidgets('celebrates only a paid server result', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CampaignTopupVerificationScreen(
          statusReader: () async => result(CampaignTopupStatus.paid),
          pollDelays: const [Duration.zero],
          successDelay: const Duration(days: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('topup-paid')), findsOneWidget);
    expect(find.text('Money added'), findsOneWidget);
    expect(find.textContaining('R 10.00'), findsOneWidget);
  });

  testWidgets('checking lets the merchant return to Money immediately', (
    tester,
  ) async {
    CampaignTopupStatus? returned;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              returned = await Navigator.of(context).push<CampaignTopupStatus>(
                MaterialPageRoute(
                  builder: (_) => CampaignTopupVerificationScreen(
                    statusReader: () =>
                        Completer<CampaignTopupStatusResult>().future,
                    pollDelays: const [Duration.zero],
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Back to Money'), findsOneWidget);
    await tester.tap(find.text('Back to Money'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(returned, CampaignTopupStatus.checking);
  });

  for (final entry in <CampaignTopupStatus, String>{
    CampaignTopupStatus.failed: 'Payment not completed',
    CampaignTopupStatus.expired: 'Payment not completed',
    CampaignTopupStatus.needsReview: 'Payment needs checking',
    CampaignTopupStatus.refundPending: 'Refund in progress',
    CampaignTopupStatus.refunded: 'Payment refunded',
  }.entries) {
    testWidgets('${entry.key.name} never renders a paid celebration', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CampaignTopupVerificationScreen(
            statusReader: () async => result(entry.key),
            pollDelays: const [Duration.zero],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.byKey(const ValueKey('topup-paid')), findsNothing);
      expect(find.text('Money added'), findsNothing);
    });
  }
}
