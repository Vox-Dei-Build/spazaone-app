import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/actions_block.dart';

void main() {
  testWidgets('shows cancel button for cash orders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionsBlock(
            paymentMethod: 'cash',
            isPaid: false,
            isBnpl: false,
            isBnplApproved: false,
            isCancelled: false,
            isRejected: false,
            onAcceptBnpl: () {},
            onRejectBnpl: () {},
            onMarkCash: () {},
            onSettleBnpl: () {},
            onMarkCollected: () {},
            onCancelOrder: () {},
            showMarkCollected: false,
          ),
        ),
      ),
    );
    expect(find.text('Cancel Order'), findsOneWidget);
  });

  testWidgets('shows cancel button for BNPL orders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionsBlock(
            paymentMethod: 'bnpl',
            isPaid: false,
            isBnpl: true,
            isBnplApproved: false,
            isCancelled: false,
            isRejected: false,
            onAcceptBnpl: () {},
            onRejectBnpl: () {},
            onMarkCash: () {},
            onSettleBnpl: () {},
            onMarkCollected: () {},
            onCancelOrder: () {},
            showMarkCollected: false,
          ),
        ),
      ),
    );
    expect(find.text('Cancel Order'), findsOneWidget);
  });

  testWidgets('shows payment first for an unpaid EFT pickup', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionsBlock(
            paymentMethod: 'eft',
            isPaid: false,
            isBnpl: false,
            isBnplApproved: false,
            isCancelled: false,
            isRejected: false,
            onAcceptBnpl: () {},
            onRejectBnpl: () {},
            onMarkCash: () {},
            onSettleBnpl: () {},
            onMarkCollected: () {},
            onCancelOrder: () {},
            showMarkCollected: false,
            showMarkCash: true,
          ),
        ),
      ),
    );

    expect(find.text('Mark Payment Received'), findsOneWidget);
    expect(find.text('Mark Collected'), findsNothing);
    expect(find.textContaining('before handing over'), findsOneWidget);
  });

  testWidgets('shows collection only after EFT is paid', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionsBlock(
            paymentMethod: 'eft',
            isPaid: true,
            isBnpl: false,
            isBnplApproved: false,
            isCancelled: false,
            isRejected: false,
            onAcceptBnpl: () {},
            onRejectBnpl: () {},
            onMarkCash: () {},
            onSettleBnpl: () {},
            onMarkCollected: () {},
            onCancelOrder: () {},
            showMarkCollected: true,
            showMarkCash: false,
          ),
        ),
      ),
    );

    expect(find.text('Mark Collected'), findsOneWidget);
    expect(find.text('Mark Payment Received'), findsNothing);
  });
}
