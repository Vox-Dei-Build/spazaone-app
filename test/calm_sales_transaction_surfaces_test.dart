import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/sales/widgets/add_sale.dart';
import 'package:pasella/pages/transactions/view_transaction/view_transaction.dart';
import 'package:pasella/utils/currency_util.dart';

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
      theme: kCustomThemeData,
      builder: (context, built) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: built!,
      ),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('Record Sale shows essentials before optional work',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final amount = TextEditingController();
    final stock = TextEditingController();
    final notes = TextEditingController();
    addTearDown(amount.dispose);
    addTearDown(stock.dispose);
    addTearDown(notes.dispose);

    await tester.pumpWidget(_app(
      Form(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: RecordSaleFields(
            amountController: amount,
            selectedDate: DateTime.now(),
            onDateChanged: (_) {},
            stockAmountController: stock,
            invoiceField: const Text('Invoice controls'),
            productField: const Text('Product controls'),
            notesController: notes,
          ),
        ),
      ),
      textScale: 2,
    ));

    expect(find.text('Sales amount'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Add restocking'), findsOneWidget);
    expect(find.text('Add products'), findsOneWidget);
    expect(find.text('Add a note'), findsOneWidget);
    expect(find.text('Stock amount (optional)'), findsNothing);
    expect(find.text('Invoice controls'), findsNothing);
    expect(find.text('Product controls'), findsNothing);
    expect(find.text('Optional note'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Add restocking'));
    await tester.pumpAndSettle();
    expect(find.text('Stock amount (optional)'), findsOneWidget);
    expect(find.text('Invoice controls'), findsOneWidget);

    await tester.ensureVisible(find.text('Add products'));
    await tester.tap(find.text('Add products'));
    await tester.pumpAndSettle();
    expect(find.text('Product controls'), findsOneWidget);

    await tester.ensureVisible(find.text('Add a note'));
    await tester.tap(find.text('Add a note'));
    await tester.pumpAndSettle();
    expect(find.text('Optional note'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transaction details emphasize amount and hide empty sections',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(
      TransactionDetailsContent(
        customerName: 'Naledi Mokoena',
        transaction: {
          'type': 'Credit',
          'amount': 420,
          'status': 'DUE',
          'date': DateTime(2026, 9, 5, 14, 30),
          'repaymentDate': DateTime(2026, 9, 25),
          'products': const <String, dynamic>{},
          'remarks': '',
        },
      ),
      textScale: 2,
    ));

    expect(find.text(CurrencyUtil.format(420)), findsOneWidget);
    expect(find.text('Due'), findsOneWidget);
    expect(find.text('Due date'), findsOneWidget);
    expect(find.text('Note'), findsNothing);
    expect(find.text('Products'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_app(
      TransactionDetailsContent(
        customerName: 'Naledi Mokoena',
        transaction: {
          'type': 'Payment',
          'amount': 150,
          'status': 'PAID',
          'date': DateTime(2026, 9, 5, 14, 30),
          'paymentMethod': 'cash',
        },
      ),
      textScale: 2,
    ));
    await tester.pump();

    expect(find.text(CurrencyUtil.format(150)), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Payment method'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
