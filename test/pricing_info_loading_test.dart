import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/wallet/tabs/pricing_tab.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';

const _messages = MessagingPricingSnapshotV1(
  smsCustomerMinor: 174,
  smsPaymentMinor: 174,
  whatsappUtilityMinor: 20,
  whatsappPromotionMinor: 100,
);
const _fees = OnlinePaymentFees(
    localPercent: 2.9,
    localFlat: 1,
    eftPercent: 2,
    internationalPercent: 3.1,
    internationalFlat: 1,
    vat: 15);

void main() {
  testWidgets(
      'message access error does not hide loaded payment fees and retry recovers',
      (tester) async {
    var messageLoads = 0;
    var paymentLoads = 0;
    await tester.pumpWidget(MaterialApp(
        theme: kCustomThemeData,
        home: Scaffold(
          body: PricingInfoTab(
            loadMessagingPricing: () async {
              if (++messageLoads == 1) {
                throw FirebaseFunctionsException(
                    code: 'failed-precondition',
                    message: 'App verification is required.');
              }
              return _messages;
            },
            loadPaymentFees: () async {
              paymentLoads++;
              return _fees;
            },
          ),
        )));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('This app could not be verified'), findsOneWidget);
    expect(find.text('R0,00'), findsNothing);
    await tester.tap(find.text('Online payments').first);
    await tester.pumpAndSettle();
    expect(find.text('Local card'), findsOneWidget);
    expect(find.text('2.9% + R1,00 + VAT'), findsOneWidget);
    await tester.tap(find.text('Messages').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again').first);
    await tester.pumpAndSettle();
    expect(messageLoads, 2);
    expect(paymentLoads, 1);
    expect(find.text('R1,74'), findsNWidgets(2));
    expect(find.textContaining('This app could not be verified'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slow message request does not block payment section',
      (tester) async {
    final messageRequest = Completer<MessagingPricingSnapshotV1>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PricingInfoTab(
      loadMessagingPricing: () => messageRequest.future,
      loadPaymentFees: () async => _fees,
    ))));
    await tester.pump();
    await tester.tap(find.text('Online payments').first);
    await tester.pump();
    expect(find.text('Local card'), findsOneWidget);
    messageRequest.complete(_messages);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('price error and retry remain readable at 320px and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
          body: PricingInfoTab(
        loadMessagingPricing: () async => throw FirebaseFunctionsException(
            code: 'permission-denied', message: 'No access'),
        loadPaymentFees: () async => _fees,
      )),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Try again'), 220,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('messaging-costs-page')),
          matching: find.byType(Scrollable),
        ));
    expect(find.textContaining('You do not have access'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
