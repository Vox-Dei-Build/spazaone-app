import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/ledger/widgets/transaction_tile.dart';
import 'package:pasella/pages/transactions/widgets/customer_balance_hero.dart';
import 'package:pasella/pages/transactions/widgets/pay_later_action_bar.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/pages/transactions/transactions_management/transactions_management.dart';
import '../tool/customer_design_previews.dart';

void main() {
  testWidgets('customer list keeps compact rows and balances on the right',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: Builder(builder: customerDesignPreviews()['Customers']!),
    ));
    await tester.pumpAndSettle();
    final rows = find.byType(TransactionTile);
    expect(rows, findsNWidgets(4));
    final balanceRights = <double>[];
    for (var index = 0; index < 4; index++) {
      final row = rows.at(index);
      expect(tester.getSize(row).height, lessThanOrEqualTo(80));
      final amount = find.descendant(
          of: row,
          matching: find.byKey(const ValueKey('customer-row-balance')));
      balanceRights.add(tester.getRect(amount).right);
    }
    expect(balanceRights.every((right) => (right - 374).abs() < 1), isTrue);
    await tester.tap(find.text('Naledi Mokoena'));
    await tester.pumpAndSettle();
    expect(find.text('Add to account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'customer gallery routes use production presentation at 320px200%',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final route in customerDesignPreviews().entries) {
      await tester.pumpWidget(MaterialApp(
        theme: kCustomThemeData,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(builder: route.value),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: route.key);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'customer row keeps identity, unread count and full balance at large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
              body: SingleChildScrollView(
                  child: TransactionTile(
            color: 0,
            name: 'A customer with a long family name',
            amount: 0,
            remarks: 'No transactions yet',
            status: '',
            type: 'Credit',
            date: '',
            selectedCustomerId: 'sample',
            balance: -1234567.89,
            unreadCount: 120,
            onTap: () => taps++,
          )))),
    ));
    expect(find.text('A customer with a long family name'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text(CurrencyUtil.format(1234567.89)), findsOneWidget);
    expect(find.text('Owes you'), findsOneWidget);
    await tester.ensureVisible(find.text('Owes you'));
    await tester.tap(find.text('Owes you'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'account actions remain tappable in short landscape with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var credits = 0, payments = 0;
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: Scaffold(
        body: const SingleChildScrollView(
            child: CustomerBalanceCard(
                balance: -270, creditCount: 1, paymentCount: 1)),
        bottomNavigationBar: CustomerAccountActions(
            onAddCredit: () => credits++, onRecordPayment: () => payments++),
      ),
    ));
    await tester.tap(find.text('Add to account'));
    await tester.tap(find.text('Record payment'));
    expect(credits, 1);
    expect(payments, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short account layout scrolls to balance and payment requests',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var requests = 0;
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: Scaffold(
          body: CustomerAccountLayout(
        transactions: ListView(children: const [Text('Ledger entry')]),
        balance: const CustomerBalanceCard(
            balance: -270, creditCount: 1, paymentCount: 1),
        requestPanel: FilledButton(
            onPressed: () => requests++, child: const Text('Request payment')),
      )),
    ));
    await tester.ensureVisible(find.text('Request payment'));
    await tester.tap(find.text('Request payment'));
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });
}
