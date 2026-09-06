import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/utils/wallet_utils.dart';

Widget _app(Widget child) => MaterialApp(
      theme: kCustomThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: child,
    );

void main() {
  testWidgets(
      'pending check and repayment actions fit at 320px with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var checks = 0;
    var views = 0;
    await tester.pumpWidget(_app(Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            WalletPendingPaymentActivity(onCheckAgain: () => checks++),
            WalletRepaymentNotice(
              totalOwed: 'R123 456 789,99',
              onView: () => views++,
            ),
          ],
        ),
      ),
    )));
    expect(
      find.text('Your SpazaOne balance will update only after confirmation.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Check'));
    await tester.tap(find.text('Check'));
    expect(checks, 1);
    await tester.ensureVisible(find.text('View'));
    await tester.tap(find.text('View'));
    expect(views, 1);
    expect(
      tester.getRect(find.text('R123 456 789,99')).right,
      lessThanOrEqualTo(320),
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    testWidgets('repayment details and report remain reachable at $size',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var reports = 0;
      const breakdown = WalletBreakdown(
        advanceFee: 'R50,00',
        bankFee: 'R25,00',
        penaltyFee: 'No penalty',
        amountDue: 'R900,00',
        totalOwed: 'R1 250,00',
        dueDate: '30 September 2026',
        suspended: 'No',
      );
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              useSafeArea: true,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (context) => WalletRepaymentDetailsSheet(
                breakdown: breakdown,
                onClose: () => Navigator.of(context).pop(),
                onViewReport: () => reports++,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      )));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Amount Due'), findsOneWidget);
      expect(find.text(breakdown.totalOwed), findsOneWidget);
      expect(find.text(breakdown.amountDue), findsNothing);
      expect(find.text('No penalty'), findsOneWidget);
      await tester.ensureVisible(find.text('View Full Report'));
      await tester.tap(find.text('View Full Report'));
      expect(reports, 1);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close repayment details'));
      await tester.pumpAndSettle();
      expect(find.text('Repayment Details'), findsNothing);
    });
  }
}
