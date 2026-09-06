import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/full_repayment_report.dart';
import 'package:pasella/utils/wallet_utils.dart';

void main() {
  testWidgets(
      'repayment overview and long history remain reachable at 320px/2x',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = WalletState(
      balance: 0,
      hasBankAccount: true,
      hasPendingPayout: false,
      cashAdvanceBalance: 0,
      salesVirtualBalance: 0,
      cashAdvanceWithdrawn: 100,
      penaltyFee: 0,
      accountSuspended: false,
      cashAdvanceDueDate: DateTime(2026, 9, 30),
      totalCashAdvanceGiven: 100,
      totalCashAdvanceRepaid: 50,
      repaymentHistory: [
        {
          'amount': 50,
          'date': DateTime(2026, 9, 4),
          'method': 'Instant EFT',
          'status': 'Completed',
          'reference': 'EXAMPLE-REFERENCE-THAT-NEEDS-TO-WRAP',
        }
      ],
    );
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: FullRepaymentReportPage(
        walletState: state,
        breakdownLoader: (_) async => const WalletBreakdown(
          advanceFee: 'R10,00',
          bankFee: 'R2,00',
          penaltyFee: 'R0,00',
          amountDue: 'R50,00',
          totalOwed: 'R62,00',
          dueDate: '30 September',
          suspended: 'No',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
        find.textContaining('EXAMPLE-REFERENCE'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('EXAMPLE-REFERENCE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
