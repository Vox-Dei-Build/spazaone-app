import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/pages/sales/models/sale_edit_result.dart';
import 'package:pasella/pages/sales/widgets/sale_detail_page.dart';
import 'package:pasella/pages/transactions/view_transaction/view_transaction.dart';
import 'package:pasella/utils/currency_util.dart';

void main() {
  testWidgets('transaction editor receives the latest loaded transaction',
      (tester) async {
    var loadCount = 0;
    final editedAmounts = <num>[];

    Future<Map<String, dynamic>?> loadTransaction() async {
      loadCount++;
      return {
        'type': 'Payment',
        'amount': loadCount == 1 ? 200 : 300,
        'status': 'PAID',
        'date': DateTime(2026, 9, 6, 10),
        'paymentMethod': 'cash',
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: kCustomThemeData,
        home: TransactionDetailScreen(
          customerName: 'Naledi',
          customerId: 'customer-1',
          transactionId: 'transaction-1',
          transaction: const {
            'type': 'Payment',
            'amount': 100,
            'status': 'PAID',
          },
          loadTransaction: loadTransaction,
          editTransactionBuilder: (transaction) {
            editedAmounts.add(transaction['amount'] as num);
            return const _FakeTransactionEditor();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(CurrencyUtil.format(200)), findsOneWidget);
    await tester.tap(find.byTooltip('Edit transaction'));
    await tester.pumpAndSettle();
    expect(editedAmounts, [200]);

    await tester.tap(find.text('Finish edit'));
    await tester.pumpAndSettle();
    expect(find.text(CurrencyUtil.format(300)), findsOneWidget);

    await tester.tap(find.byTooltip('Edit transaction'));
    await tester.pumpAndSettle();
    expect(editedAmounts, [200, 300]);
  });

  testWidgets('sale update refreshes details and deletion closes once',
      (tester) async {
    final editorInputs = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: kCustomThemeData,
        home: _SaleDetailHarness(
          editSaleBuilder: (sale) {
            editorInputs.add(sale.amount);
            return _FakeSaleEditor(sale: sale);
          },
        ),
      ),
    );

    await tester.tap(find.text('Open sale'));
    await tester.pumpAndSettle();
    expect(find.text(CurrencyUtil.format(100)), findsOneWidget);

    await tester.tap(find.byTooltip('Edit sale'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply update'));
    await tester.pumpAndSettle();

    expect(find.text('Sale details'), findsOneWidget);
    expect(find.text(CurrencyUtil.format(150)), findsOneWidget);
    expect(editorInputs, [100]);

    await tester.tap(find.byTooltip('Edit sale'));
    await tester.pumpAndSettle();
    expect(editorInputs, [100, 150]);
    await tester.tap(find.text('Delete sale'));
    await tester.pumpAndSettle();

    expect(find.text('Open sale'), findsOneWidget);
    expect(find.text('Detail changed: true'), findsOneWidget);
    expect(find.text('Sale details'), findsNothing);
  });
}

class _FakeTransactionEditor extends StatelessWidget {
  const _FakeTransactionEditor();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Finish edit'),
          ),
        ),
      );
}

class _SaleDetailHarness extends StatefulWidget {
  const _SaleDetailHarness({required this.editSaleBuilder});

  final Widget Function(Sale sale) editSaleBuilder;

  @override
  State<_SaleDetailHarness> createState() => _SaleDetailHarnessState();
}

class _SaleDetailHarnessState extends State<_SaleDetailHarness> {
  bool? changed;

  Sale get sale => Sale(
        id: 'sale-1',
        amount: 100,
        stockAmount: 40,
        type: 'Cash',
        products: const {},
        dateAdded: DateTime(2026, 9, 6, 10),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => SaleDetailPage(
                        sale: sale,
                        editSaleBuilder: widget.editSaleBuilder,
                      ),
                    ),
                  );
                  if (mounted) setState(() => changed = result);
                },
                child: const Text('Open sale'),
              ),
              Text('Detail changed: $changed'),
            ],
          ),
        ),
      );
}

class _FakeSaleEditor extends StatelessWidget {
  const _FakeSaleEditor({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  SaleEditResult.updated(
                    Sale(
                      id: sale.id,
                      amount: sale.amount + 50,
                      stockAmount: sale.stockAmount,
                      type: sale.type,
                      products: sale.products,
                      dateAdded: sale.dateAdded,
                      remarks: sale.remarks,
                      stockInvoices: sale.stockInvoices,
                    ),
                  ),
                ),
                child: const Text('Apply update'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  const SaleEditResult.deleted(),
                ),
                child: const Text('Delete sale'),
              ),
            ],
          ),
        ),
      );
}
