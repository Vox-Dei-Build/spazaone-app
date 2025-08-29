import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/utils/support_util.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pasella/config/size_config.dart';

class PricingInfoTab extends StatefulWidget {
  const PricingInfoTab({super.key});

  @override
  _PricingInfoTab createState() => _PricingInfoTab();
}

class _PricingInfoTab extends State<PricingInfoTab> {
  DynamicPricingService? pricingService;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    initialisePricingService();
  }

  Future<void> initialisePricingService() async {
    final service = await DynamicPricingService.initialize();
    setState(() {
      pricingService = service;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final rc = pricingService?.remoteConfigService;
    final localPercent = rc?.getDouble('PAYSTACK_LOCAL_PERCENT') ?? 0;
    final localFlat = rc?.getDouble('PAYSTACK_LOCAL_FLAT') ?? 0;
    final eftPercent = rc?.getDouble('PAYSTACK_EFT_PERCENT') ?? 0;
    final intPercent = rc?.getDouble('PAYSTACK_INT_PERCENT') ?? 0;
    final intFlat = rc?.getDouble('PAYSTACK_INT_FLAT') ?? 0;
    final settlementFee = rc?.getDouble('PAYSTACK_SETTLEMENT_FEE') ?? 0;
    final vatPercent = rc?.getDouble('PAYSTACK_VAT_PERCENT') ?? 0;

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 🟢 Section 1: How It Works
            _sectionTitle('How It Works'),

            _buildBulletPoint(
                '📊 Viewing balance - Always visible at the top of your wallet.'),

            _buildBulletPoint(
                '📜 Transaction history - View payments & expenses anytime.'),

            if (FeatureFlags.enableBalancePayout) ...[
              _buildBulletPoint(
                  '📌 Set up banking details to receive payouts.'),
              _buildBulletPoint(
                  '💰 Request payouts - Withdraw balance whenever needed.'),
            ],

            // 🟢 Section 3: Payouts (Dynamic)
            if (FeatureFlags.enableBalancePayout) ...[
              _sectionTitle('Payouts'),
              _buildBulletPoint(
                  '🕒 Request anytime - Processed during business hours.'),
              _buildBulletPoint('🔍 Track payout status in real-time.'),
              _buildBulletPoint('🏧 Funds sent to your linked bank account.'),
              SizedBox(height: SizeConfig.heightMultiplier * 3),
            ],

            // 🟢 Section 4: Messaging Pricing & Fees
            if (FeatureFlags.enablePricingInfo) ...[
              _sectionTitle('Messaging Pricing & Fees'),
              _buildBulletPoint(
                  '💬 Charged per message sent (WhatsApp & SMS).'),
              SizedBox(height: SizeConfig.heightMultiplier * 1),
              _pricingRow('Reminder SMS',
                  '${CurrencyUtil.format(pricingService?.smsReminderTemplatePrice ?? 0)}/SMS'),
              _pricingRow('WhatsApp Reminder',
                  '${CurrencyUtil.format(pricingService?.whatsappUtilityPrice ?? 0)}/Msg'),
              _divider(),
              _pricingRow('Credit SMS',
                  '${CurrencyUtil.format(pricingService?.smsReminderTemplatePrice ?? 0)}/SMS'),
              _pricingRow('WhatsApp Credit',
                  '${CurrencyUtil.format(pricingService?.whatsappUtilityPrice ?? 0)}/Msg'),
              _divider(),
              _pricingRow('Payment SMS',
                  '${CurrencyUtil.format(pricingService?.smsPaymentTemplatePrice ?? 0)}/SMS'),
              _pricingRow('WhatsApp Payment',
                  '${CurrencyUtil.format(pricingService?.whatsappUtilityPrice ?? 0)}/Msg'),
              _divider(),
              _pricingRow('Onboarding SMS',
                  '${CurrencyUtil.format(pricingService?.smsReminderTemplatePrice ?? 0)}/SMS'),
              _pricingRow('WhatsApp Onboarding',
                  '${CurrencyUtil.format(pricingService?.whatsappUtilityPrice ?? 0)}/Msg'),
              _divider(),
              _pricingRow('SMS Promotions', 'Based on length of Msg'),
              _pricingRow('WhatsApp Promotions',
                  '${CurrencyUtil.format(pricingService?.whatsappPromotionPrice ?? 0)}/Msg'),
              _pricingRow('Whatsapp AI Assistant',
                  '${CurrencyUtil.format(pricingService?.whatsappUtilityPrice != null ? pricingService!.whatsappUtilityPrice + 0.05 : 0)}/Msg'),
              SizedBox(height: SizeConfig.heightMultiplier * 3),
            ],

            // 🟢 Section 5: Order Payments & Fees
            if (FeatureFlags.enablePricingInfo) ...[
              _sectionTitle('Order Payments & Fees'),
              _buildBulletPoint(
                  '🛍️ Cash orders settle immediately with no platform fee.'),
              _buildBulletPoint(
                  '💳 Online orders incur a platform fee and transaction fee.'),
              _buildBulletPoint(
                  '📲 Wallet balance can be used for in-app purchases.'),
              SizedBox(height: SizeConfig.heightMultiplier * 3),
            ],

            // 🟢 Section 6: Paystack Fees (South Africa)
            if (FeatureFlags.enablePricingInfo &&
                FeatureFlags.enableTopUpPaystack) ...[
              _sectionTitle('Paystack Fees (South Africa)'),
              _buildBulletPoint(
                  'Local Payments: ${localPercent.toStringAsFixed(1)}% + R${localFlat.toStringAsFixed(2)} (excl. VAT)'),
              _buildBulletPoint(
                  'Bank EFT: ${eftPercent.toStringAsFixed(1)}% (excl. VAT)'),
              _buildBulletPoint(
                  'International Payments: ${intPercent.toStringAsFixed(1)}% + R${intFlat.toStringAsFixed(2)} (excl. VAT)'),
              _buildBulletPoint(
                  'Settlement (Payouts): R${settlementFee.toStringAsFixed(2)} per transfer (excl. VAT)'),
              SizedBox(height: SizeConfig.heightMultiplier * 3),
              _sectionTitle('Worked Examples'),
              _exampleTransaction(
                  'Example 1: Local Card Transaction — R1 000 sale',
                  1000,
                  localPercent,
                  localFlat,
                  vatPercent),
              _exampleTransaction('Example 2: EFT Transaction — R1 000 sale',
                  1000, eftPercent, 0, vatPercent),
              _exampleTransaction('Example 3: International Card — R1 000 sale',
                  1000, intPercent, intFlat, vatPercent),
              SizedBox(height: SizeConfig.heightMultiplier * 3),
            ],

            SizedBox(height: SizeConfig.heightMultiplier * 3),
            // 🟢 Section 6: Need Help?
            _sectionTitle('Need Help?'),
            _helpOption('0648370009'),
          ],
        ),
      ),
    );
  }

  Widget _exampleTransaction(
      String title, double sale, double percent, double flat, double vat) {
    final base = sale * percent / 100;
    final subtotal = base + flat;
    final vatAmount = subtotal * vat / 100;
    final total = subtotal + vatAmount;
    final merchant = sale - total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBulletPoint(title),
        _buildBulletPoint(
            'Base fee: ${percent.toStringAsFixed(1)}% of ${sale.toStringAsFixed(0)} = R${base.toStringAsFixed(2)}'),
        if (flat > 0)
          _buildBulletPoint(
              'Flat: R${flat.toStringAsFixed(2)} → R${subtotal.toStringAsFixed(2)}'),
        _buildBulletPoint(
            'VAT: ${vat.toStringAsFixed(0)}% of R${subtotal.toStringAsFixed(2)} = R${vatAmount.toStringAsFixed(2)}'),
        _buildBulletPoint('Total fee = R${total.toStringAsFixed(2)}'),
        _buildBulletPoint(
            'Merchant receives = R${merchant.toStringAsFixed(2)}'),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
      ],
    );
  }

  // ✅ Title Section
  Widget _sectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: SizeConfig.heightMultiplier * 1.5),
      child: Text(
        title,
        style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 2,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            decoration: TextDecoration.none),
      ),
    );
  }

  // ✅ Simple Divider
  Widget _divider() {
    return Divider(
        thickness: 1,
        height: SizeConfig.heightMultiplier * 2,
        color: Colors.grey);
  }

  // ✅ Bullet Points with Spacing & Icons
  Widget _buildBulletPoint(String text) {
    return Padding(
      padding:
          EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 0.8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.8, height: 1),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Pricing Row for Fees
  Widget _pricingRow(String title, String price) {
    return Padding(
      padding:
          EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.5)),
          Text(price,
              style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.5,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ✅ WhatsApp Help Option
  Widget _helpOption(String phone) {
    return FilledButton.icon(
      onPressed: () =>
          SupportUtil.sendWhatsAppMessage(context, WhatsAppMessageType.support),
      icon:
          Icon(FontAwesomeIcons.whatsapp, size: SizeConfig.textMultiplier * 2),
      label: Text("Chat to support",
          style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
    );
  }

  void _launchWhatsApp(String phone) async {
    final url = "https://wa.me/$phone";
    if (await canLaunch(url)) await launch(url);
  }
}
