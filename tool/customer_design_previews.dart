// Safe gallery routes: production presentation with synthetic data only.
import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/contact/connect/widgets/message_list_view.dart';
import 'package:pasella/pages/ledger/widgets/transaction_tile.dart';
import 'package:pasella/pages/reports/customer_report/widgets/customer_report_panel.dart';
import 'package:pasella/pages/transactions/add_credit/add_credit.dart';
import 'package:pasella/pages/transactions/add_payment/add_payment.dart';
import 'package:pasella/pages/transactions/view_transaction/view_transaction.dart';
import 'package:pasella/pages/transactions/widgets/customer_balance_hero.dart';
import 'package:pasella/pages/transactions/widgets/pay_later_action_bar.dart';
import 'package:pasella/pages/transactions/widgets/repayment_plan_sheet.dart';
import 'package:pasella/pages/transactions/widgets/transaction_card.dart';
import 'package:pasella/pages/transactions/widgets/transaction_date.dart';
import 'package:pasella/shared/widgets/forms/transaction_form_scaffold.dart';

Map<String, WidgetBuilder> customerDesignPreviews() => {
      'Customers': (_) => const _CustomersPreview(),
      'Customer account': (_) => const _AccountPreview(),
      'Customer messages': (_) => const _MessagesPreview(),
      'Add to customer account': (_) => const _CreditPreview(),
      'Record customer payment': (_) => const _PaymentPreview(),
      'Pay later details': (_) => _frame(
            'Pay later details',
            TransactionDetailsContent(
              customerName: 'Naledi Mokoena',
              transaction: {
                ..._transactions.first,
                'status': 'DUE',
                'repaymentDate': DateTime(2026, 9, 25),
                'remarks': 'Weekly groceries',
              },
            ),
          ),
      'Payment details': (_) => _frame(
            'Payment details',
            TransactionDetailsContent(
              customerName: 'Naledi Mokoena',
              transaction: {
                ..._transactions.last,
                'status': 'PAID',
                'paymentMethod': 'cash',
              },
            ),
          ),
      'Repayment plan': (_) => const _PlanPreview(),
      'Customer insights': (_) => _frame(
            'Customer insights',
            CustomerReportContent(
              customerName: 'Naledi Mokoena',
              transactions: _transactions,
            ),
          ),
    };

final _day = DateTime(2026, 9, 5);
final _transactions = <Map<String, dynamic>>[
  {
    'id': 'sample-credit',
    'type': 'Credit',
    'amount': 420.0,
    'date': DateTime(2026, 8, 25, 9, 15).toIso8601String(),
    'products': <String, dynamic>{}
  },
  {
    'id': 'sample-payment',
    'type': 'Payment',
    'amount': 150.0,
    'date': _day.add(const Duration(hours: 14, minutes: 30)).toIso8601String(),
    'products': <String, dynamic>{}
  },
];

Widget _frame(String title, Widget body, {Widget? actions}) => Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: Builder(
            builder: (context) => IconButton(
                  tooltip: 'Back',
                  icon: const Icon(SpazaIcons.back),
                  onPressed: () => Navigator.of(context).maybePop(),
                )),
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: actions,
    );

void _notice(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Example data only. Nothing was saved or sent.')),
    );

class _CustomersPreview extends StatelessWidget {
  const _CustomersPreview();
  @override
  Widget build(BuildContext context) => _frame(
      'Customers',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final customer in [
            ('Naledi Mokoena', -270.0, '082 123 4567', true, 2),
            ('Sipho Dlamini', -85.0, '073 555 0123', false, 0),
            ('Thandi Nkosi', 0.0, '083 555 0184', true, 0),
            ('Mpho Sithole', 40.0, '', false, 0),
          ])
            TransactionTile(
              color: kTertiaryColor.toARGB32(),
              name: customer.$1,
              amount: 150,
              remarks: 'Groceries',
              status: 'Paid',
              type: 'Payment',
              date: '5 Sep',
              selectedCustomerId: 'sample-${customer.$1}',
              balance: customer.$2,
              number: customer.$3,
              unreadCount: customer.$5,
              showChannelCapability: true,
              hasWhatsApp: customer.$4,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const _AccountPreview())),
            ),
        ],
      ));
}

class _AccountPreview extends StatelessWidget {
  const _AccountPreview();
  @override
  Widget build(BuildContext context) => _frame(
        'Naledi Mokoena',
        ListView(padding: const EdgeInsets.all(16), children: [
          const CustomerBalanceCard(
              balance: -270, creditCount: 1, paymentCount: 1),
          const SizedBox(height: 16),
          const TransactionDate('2026-08-25'),
          TransactionCard(_transactions.first),
          const TransactionDate('2026-09-05'),
          TransactionCard(_transactions.last),
        ]),
        actions: CustomerAccountActions(
          onAddCredit: () => _notice(context),
          onRecordPayment: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _PaymentPreview())),
        ),
      );
}

class _MessagesPreview extends StatelessWidget {
  const _MessagesPreview();
  @override
  Widget build(BuildContext context) => _frame(
      'Messages · Naledi',
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: MessagesListView(customerName: 'Naledi Mokoena', messages: [
          {
            'id': 'message-1',
            'message': 'Hi, could you please check my account balance?',
            'direction': 'inbound',
            'isWhatsApp': true,
            'dateSent': _day.add(const Duration(hours: 14, minutes: 20))
          },
          {
            'id': 'message-2',
            'message':
                'Your account balance is *R270,00*. Thank you for your payment today.',
            'direction': 'outbound',
            'isWhatsApp': true,
            'status': 'read',
            'dateSent': _day.add(const Duration(hours: 14, minutes: 32))
          },
          {
            'id': 'message-3',
            'message': 'Thank you. I will pay the rest on Friday.',
            'direction': 'inbound',
            'isWhatsApp': true,
            'dateSent': _day.add(const Duration(hours: 14, minutes: 34))
          },
        ]),
      ));
}

class _PaymentPreview extends StatefulWidget {
  const _PaymentPreview();
  @override
  State<_PaymentPreview> createState() => _PaymentPreviewState();
}

class _PaymentPreviewState extends State<_PaymentPreview> {
  final _amount = TextEditingController(text: '150');
  final _notes = TextEditingController();
  final _form = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  String _method = 'cash';
  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _frame(
      'Record payment',
      Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          CustomerPaymentFields(
            customerName: 'Naledi Mokoena',
            amountController: _amount,
            remarksController: _notes,
            selectedDate: _date,
            paymentMethod: _method,
            onDateChanged: (value) => setState(() => _date = value),
            onPaymentMethodChanged: (value) => setState(() => _method = value),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              if (_form.currentState!.validate()) _notice(context);
            },
            icon: const Icon(Icons.arrow_upward_rounded),
            label: const Text('Record payment'),
          ),
        ]),
      ));
}

class _CreditPreview extends StatefulWidget {
  const _CreditPreview();

  @override
  State<_CreditPreview> createState() => _CreditPreviewState();
}

class _CreditPreviewState extends State<_CreditPreview> {
  final _amount = TextEditingController(text: '420');
  final _notes = TextEditingController();
  final _form = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TransactionFormScaffold(
        title: 'Add to account',
        formKey: _form,
        primaryActionLabel: 'Add to account',
        primaryActionIcon: Icons.arrow_downward_rounded,
        onPrimaryAction: () => _notice(context),
        body: CreditTransactionFields(
          customerName: 'Naledi Mokoena',
          amountController: _amount,
          selectedDate: _date,
          repaymentDate: _dueDate,
          onDateChanged: (value) => setState(() => _date = value),
          onRepaymentDateChanged: (value) => setState(() => _dueDate = value),
          productField: OutlinedButton.icon(
            onPressed: () => _notice(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Choose products'),
          ),
          notesController: _notes,
        ),
      );
}

class _PlanPreview extends StatelessWidget {
  const _PlanPreview();
  @override
  Widget build(BuildContext context) => _frame(
      'Repayment plan',
      const RepaymentPlanSheet(
          customerName: 'Naledi Mokoena', outstandingAmountMinor: 27000));
}
