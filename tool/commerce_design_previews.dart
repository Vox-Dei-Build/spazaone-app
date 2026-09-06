// Synthetic examples of production commerce widgets. No provider initialization,
// Firebase reads, payment starts, template submission or campaign sends.
import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/models/commerce/commerce_order.dart';
import 'package:pasella/models/wallet/banking_detail_model.dart';
import 'package:pasella/pages/wallet/widgets/add_banking_details.dart';
import 'package:pasella/services/payment_setup_service.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/amounts_card.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/header_card.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/product_card_enhanced.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/review_and_pricing/review_and_pricing_step.dart';
import 'package:pasella/pages/promote/widgets/templates/template_picker_card.dart';
import 'package:pasella/pages/sales/widgets/combined_online_orders.dart';
import 'package:pasella/pages/sales/widgets/online_sale_detail_page.dart';
import 'package:pasella/pages/sales/widgets/online_sales_list.dart';
import 'package:pasella/pages/wallet/tabs/banking_details_tab.dart';
import 'package:pasella/pages/wallet/tabs/pricing_tab.dart';
import 'package:pasella/pages/wallet/tabs/unified_history_tab.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';

Map<String, WidgetBuilder> commerceDesignPreviews() => {
      'Online orders': (_) => const _OnlineOrdersPreview(),
      'Online receipt': (_) => _screen('Online receipt',
          OnlineSaleDetailContent(raw: _receipt, orderId: 'DEMO-1042')),
      'Customer order': (_) => _customerOrder(),
      'Money history': (_) => _moneyHistory(),
      'Bank details': (_) => const _BankDetailsPreview(),
      'Message costs': (_) => _screen(
          'Message costs',
          _scroll(const [
            Text('Example rates for design review. These are not live prices.'),
            SizedBox(height: 16),
            MessagingPricingSummary(
              smsCustomerRate: .4,
              smsPaymentRate: .4,
              whatsappUtilityRate: .25,
              whatsappPromotionRate: .6,
            ),
          ])),
      'Templates': (_) => const _TemplatesPreview(),
      'Campaign review': (_) => _screen(
            'Review promotion',
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ReviewAndPricingStep(
                templateContent:
                    'Hi {{customerName}}, fresh essentials are waiting at {{shopName}}. '
                    'Try {{productName}} for {{productPrice}}.',
                smsContent:
                    'Neighbourhood Store: Full cream milk is R18,50. Reply STOP to opt out.',
                mediaUrl: null,
                shopName: 'Neighbourhood Store',
                sendWhatsApp: true,
                sendSMS: true,
                totalCost: 19.2,
                breakdown: {
                  'whatsappCount': 24,
                  'whatsappUnit': .6,
                  'smsCount': 12,
                  'smsUnit': .4,
                  'smsSegments': 1,
                },
                linkedProduct: LinkedProductRef(
                  id: 'demo-milk',
                  name: 'Full cream milk · 1 L',
                  sellingPrice: 18.5,
                  whatsappListed: true,
                ),
              ),
            ),
          ),
    };

class _BankDetailsPreview extends StatefulWidget {
  const _BankDetailsPreview();

  @override
  State<_BankDetailsPreview> createState() => _BankDetailsPreviewState();
}

class _BankDetailsPreviewState extends State<_BankDetailsPreview> {
  BankingDetails _saved = BankingDetails(
    bankName: 'Example Bank',
    accountHolderName: 'Neighbourhood Store',
    accountNumber: '0000000000',
    accountType: 'Business',
    branchCode: '000000',
    reference: 'EXAMPLE ONLY',
  );

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => AddBankingDetailsPage(
        initialDetails: _saved,
        isEditing: true,
        onSave: (details) async => _saved = details,
        loadSupportedBanks: () async => const [
          SupportedSettlementBank(
              name: 'Example Bank',
              branchCode: '000000',
              supportedAccountTypes: ['personal', 'business']),
          SupportedSettlementBank(
              name: 'Demo Bank',
              branchCode: '000001',
              supportedAccountTypes: ['personal', 'business']),
        ],
      ),
    ));
    if (mounted && saved == true) setState(() {});
  }

  @override
  Widget build(BuildContext context) => _screen(
      'Bank details',
      _scroll([
        const Text(
            'Example details for design review. Edits stay in this preview.'),
        const SizedBox(height: 16),
        BankingDetailsPanel(details: _saved, canEdit: true, onEdit: _edit),
      ]));
}

Widget _screen(String title, Widget body) => Scaffold(
      appBar: CustomAppBar(title: title),
      body: body,
    );

Widget _scroll(List<Widget> children) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: children,
    );

final Map<String, dynamic> _receipt = {
  'id': 'DEMO-1042',
  'reference': 'Example payment',
  'status': 'paid',
  'orderTotal': 275.5,
  'amountPaid': 275.5,
  'feeInclVat': 8.5,
  'netAmount': 267,
  'method': 'eft',
  'itemsCount': 6,
  'createdAt': DateTime(2026, 9, 4, 14, 32),
  'ledgerCreatedAt': DateTime(2026, 9, 4, 14, 33),
};

Widget _customerOrder() => _screen(
    'Customer order',
    _scroll([
      const HeaderCard(
        customerName: 'Lerato Mokoena',
        statusText: 'Paid',
        statusColor: SpazaColors.action,
        totalText: 'R275,50',
        dateText: '4 September 2026 · 14:32',
        paymentMethod: 'Instant EFT',
        paymentStatus: 'Paid',
        paymentStatusColor: SpazaColors.action,
        orderId: 'DEMO-1042',
      ),
      const SizedBox(height: 16),
      const ProductCardEnhanced(
        productName: 'Full cream milk · 1 L',
        quantity: 3,
        unitPrice: 18.5,
        imageUrl: null,
      ),
      const SizedBox(height: 16),
      const AmountsCard(
          subtotal: 250.5, delivery: 25, discount: 0, total: 275.5),
    ]));

Widget _moneyHistory() => _screen(
    'Money history',
    _scroll([
      const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: BillingBalancePanel(
            campaignBalance: 250,
            salesBalance: 267,
            storeName: 'Neighbourhood Store',
            sharedCampaignCredits: false,
          ),
        ),
      ),
      const SizedBox(height: 20),
      WalletHistoryList(embedded: true, entries: [
        {
          'type': 'top-up',
          'amount': 300,
          'timestamp': DateTime(2026, 9, 4, 10)
        },
        {
          'type': 'message',
          'message':
              'Your order is ready for collection at Neighbourhood Store.',
          'messageCost': .25,
          'phone': '082 000 0000',
          'templateType': 'whatsapp',
          'timestamp': DateTime(2026, 9, 4, 9, 45),
        },
        {
          'type': 'payout',
          'amount': 267,
          'status': 'completed',
          'timestamp': DateTime(2026, 9, 3, 14, 30),
        },
      ]),
    ]));

class _OnlineOrdersPreview extends StatefulWidget {
  const _OnlineOrdersPreview();
  @override
  State<_OnlineOrdersPreview> createState() => _OnlineOrdersPreviewState();
}

class _OnlineOrdersPreviewState extends State<_OnlineOrdersPreview> {
  DateTime? day;
  DateTime? start;
  DateTime? end;

  void _notice() => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local example. No account changes.')),
      );

  @override
  Widget build(BuildContext context) => _screen(
      'Online orders',
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: CombinedOnlineOrders(
          selectedDay: day,
          startDate: start,
          endDate: end,
          onDaySelect: (value) => setState(() {
            day = value;
            start = end = null;
          }),
          onRangeSelect: (a, b) => setState(() {
            start = a;
            end = b;
            day = null;
          }),
          onClearDates: () => setState(() {
            day = start = end = null;
          }),
          onSetup: _notice,
          onShareShop: _notice,
          onOrderOptions: _notice,
          ownedLoader: ({selectedDay, startDate, endDate}) async => [
            LedgerSale.fromMap(_receipt),
            LedgerSale.fromMap({
              ..._receipt,
              'id': 'DEMO-1041',
              'status': 'pending',
              'paymentStatus': 'pending',
              'orderTotal': 120.0,
              'amountPaid': 0.0,
              'feeInclVat': 0.0,
              'netAmount': 0.0,
            }),
          ],
          supplierStream: () => Stream.value(const <CommerceOrder>[]),
          onOwnedOrderTap: (sale) => Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (_) => _screen(
                    'Online receipt',
                    OnlineSaleDetailContent(raw: {
                      ..._receipt,
                      'id': sale.id,
                      'status': sale.status,
                      'orderTotal': sale.orderTotal,
                      'amountPaid': sale.amountPaid,
                      'feeInclVat': sale.feeInclVat,
                      'netAmount': sale.netAmount,
                    }, orderId: sale.id))),
          ),
          onSupplierOrderTap: (_) => _notice(),
        ),
      ));
}

class _TemplatesPreview extends StatefulWidget {
  const _TemplatesPreview();
  @override
  State<_TemplatesPreview> createState() => _TemplatesPreviewState();
}

class _TemplatesPreviewState extends State<_TemplatesPreview> {
  int selected = 0;
  @override
  Widget build(BuildContext context) => _screen(
      'Choose a template',
      _scroll([
        for (var index = 0; index < 3; index++)
          TemplatePickerCard(
            selected: selected == index,
            onTap: () => setState(() => selected = index),
            template: {
              'name': [
                'Weekly essentials',
                'Weekend offer',
                'New product arrival'
              ][index],
              'channels': {
                'whatsapp': {
                  'approvalStatus': index == 2 ? 'pending' : 'approved',
                  'templateContent':
                      'Hi {{customerName}}, visit {{shopName}} for fresh essentials and everyday favourites.',
                },
                'sms': const {
                  'content': 'Fresh essentials at Neighbourhood Store.'
                },
              },
            },
          ),
      ]));
}
