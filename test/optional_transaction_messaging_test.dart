import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/shared/billing/cost_breakdown.dart';
import 'package:pasella/shared/billing/cost_sheet_outcome.dart';
import 'package:pasella/shared/billing/optional_transaction_messaging.dart';

const _pricing = MessagingPricingSnapshotV1(
  smsCustomerMinor: 125,
  smsPaymentMinor: 174,
  whatsappUtilityMinor: 20,
  whatsappPromotionMinor: 100,
);

Future<void> _ignorePricingError(Object _, StackTrace __) async {}

void main() {
  testWidgets('a transaction without a mobile number never requests pricing',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    var pricingRequests = 0;
    final decision = await chooseOptionalTransactionMessage(
      context,
      mobileNumber: null,
      customerName: 'Naledi',
      smsText: 'Payment received',
      smsPrice: TransactionSmsPrice.payment,
      title: 'Payment recorded',
      confirmLabel: 'Send receipt',
      loadPricing: () async {
        pricingRequests++;
        return _pricing;
      },
      reportPricingError: _ignorePricingError,
    );

    expect(pricingRequests, 0);
    expect(decision.outcome, CostSheetOutcome.skip);
    expect(decision.canSend, isFalse);
  });

  testWidgets('unavailable pricing offers save without sending or keep editing',
      (tester) async {
    CostSheetOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                final decision = await chooseOptionalTransactionMessage(
                  context,
                  mobileNumber: '0821234567',
                  customerName: 'Naledi',
                  smsText: 'Payment received',
                  smsPrice: TransactionSmsPrice.payment,
                  title: 'Payment recorded',
                  confirmLabel: 'Send receipt',
                  loadPricing: () async =>
                      throw const MessagingPricingUnavailable(),
                  reportPricingError: _ignorePricingError,
                );
                outcome = decision.outcome;
              },
              child: const Text('Submit'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Message price unavailable'), findsOneWidget);
    expect(
      find.text(
        'Save this transaction without sending a message, or keep editing.',
      ),
      findsOneWidget,
    );
    expect(find.text('Keep editing'), findsOneWidget);
    expect(find.text('Save without sending'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Save without sending'));
    await tester.pumpAndSettle();

    expect(outcome, CostSheetOutcome.skip);
    expect(outcome!.shouldCommit, isTrue);
    expect(outcome!.shouldSend, isFalse);
  });

  testWidgets('keep editing after a pricing failure does not commit',
      (tester) async {
    CostSheetOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                outcome = (await chooseOptionalTransactionMessage(
                  context,
                  mobileNumber: '0821234567',
                  customerName: 'Naledi',
                  smsText: 'Credit recorded',
                  smsPrice: TransactionSmsPrice.credit,
                  title: 'Transaction recorded',
                  confirmLabel: 'Send confirmation',
                  loadPricing: () async =>
                      throw const MessagingPricingUnavailable(),
                  reportPricingError: _ignorePricingError,
                ))
                    .outcome;
              },
              child: const Text('Submit'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    expect(outcome, CostSheetOutcome.keepEditing);
    expect(outcome!.shouldCommit, isFalse);
  });

  testWidgets('try again reloads pricing and uses the recovered server quote',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    var pricingRequests = 0;
    CostBreakdown? shownBreakdown;

    final decision = await chooseOptionalTransactionMessage(
      context,
      mobileNumber: '0821234567',
      customerName: 'Naledi',
      smsText: 'Payment received',
      smsPrice: TransactionSmsPrice.payment,
      title: 'Payment recorded',
      confirmLabel: 'Send receipt',
      loadPricing: () async {
        pricingRequests++;
        if (pricingRequests == 1) {
          throw const MessagingPricingUnavailable();
        }
        return _pricing;
      },
      resolveChannel: (_) async => MessageChannelExpectation.sms,
      showPricingUnavailable: (_) async =>
          TransactionPricingUnavailableAction.retry,
      showCostSheet: (
        _, {
        required breakdown,
        required confirmLabel,
        required skipLabel,
        required confirmDismissal,
      }) async {
        shownBreakdown = breakdown;
        return CostSheetOutcome.send;
      },
      reportPricingError: _ignorePricingError,
    );

    expect(pricingRequests, 2);
    expect(decision.outcome, CostSheetOutcome.send);
    expect(decision.canSend, isTrue);
    expect(decision.pricingSnapshot, same(_pricing));
    expect(decision.quotedTotal, 1.74);
    expect(shownBreakdown!.total, 1.74);
  });

  testWidgets('unavailable pricing can never grant permission to send',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    var pricingRequests = 0;
    var pricingPrompts = 0;
    var costSheets = 0;
    final decision = await chooseOptionalTransactionMessage(
      context,
      mobileNumber: '0821234567',
      customerName: 'Naledi',
      smsText: 'Payment received',
      smsPrice: TransactionSmsPrice.payment,
      title: 'Payment recorded',
      confirmLabel: 'Send receipt',
      loadPricing: () async {
        pricingRequests++;
        throw const MessagingPricingUnavailable();
      },
      showPricingUnavailable: (_) async {
        pricingPrompts++;
        return pricingPrompts == 1
            ? TransactionPricingUnavailableAction.retry
            : TransactionPricingUnavailableAction.keepEditing;
      },
      showCostSheet: (
        _, {
        required breakdown,
        required confirmLabel,
        required skipLabel,
        required confirmDismissal,
      }) async {
        costSheets++;
        return CostSheetOutcome.send;
      },
      reportPricingError: _ignorePricingError,
    );

    expect(pricingRequests, 2);
    expect(costSheets, 0);
    expect(decision.outcome, CostSheetOutcome.keepEditing);
    expect(decision.pricingSnapshot, isNull);
    expect(decision.quotedTotal, isNull);
    expect(decision.canSend, isFalse);
  });
}
