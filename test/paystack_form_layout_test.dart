import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/widgets/paystack_form.dart';
import 'package:pasella/services/paystack_service.dart';

void main() {
  testWidgets('Add money remains scrollable above a small-device keyboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.view.resetViewInsets();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: PaystackFormScreen(
          merchantId: 'merchant-1',
          allowedChannels: ['card'],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Add to SpazaOne balance'), findsOneWidget);
    expect(find.text('Amount to add *'), findsOneWidget);
    expect(find.text('Receipt email *'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows exactly the server-approved payment methods', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PaystackFormScreen(
          merchantId: 'merchant-1',
          allowedChannels: ['card', 'capitec_pay'],
        ),
      ),
    );

    expect(find.text('Card'), findsOneWidget);
    expect(find.text('Ozow (Instant EFT)'), findsNothing);
    expect(find.text('Scan to Pay QR'), findsNothing);
    await tester.tap(find.text('Card'));
    await tester.pumpAndSettle();
    expect(find.text('Capitec Pay'), findsOneWidget);
    expect(find.text('Ozow (Instant EFT)'), findsNothing);
    expect(find.text('Scan to Pay QR'), findsNothing);
  });

  testWidgets('fails closed when the server approves no payment method', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PaystackFormScreen(
          merchantId: 'merchant-1',
          allowedChannels: <String>[],
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('topup-channels-unavailable')),
      findsOneWidget,
    );
    expect(find.text('Card'), findsNothing);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('confirmation sheet shows exact receipt values and actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CampaignTopupConfirmationSheet(
            quote: CampaignTopupQuote(
              channel: CampaignTopupChannel.eft,
              creditAmountMinor: 10000,
              providerFeeMinor: 235,
              totalChargeMinor: 10235,
            ),
            paymentMethod: 'Ozow (Instant EFT)',
          ),
        ),
      ),
    );
    expect(find.text('Check payment details'), findsOneWidget);
    expect(find.text('R 100.00'), findsOneWidget);
    expect(find.text('R 2.35'), findsOneWidget);
    expect(find.text('R 102.35'), findsOneWidget);
    expect(find.text('Pay with Ozow'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(
      find.text(
        'We will add the money after your payment is confirmed.',
      ),
      findsOneWidget,
    );
  });
}
