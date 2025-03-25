import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/config/fees_config.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/utils/support_util.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pasella/config/size_config.dart';

class PricingInfoTab extends StatefulWidget {
  const PricingInfoTab({super.key});

  @override
  _PricingInfoTab createState() => _PricingInfoTab();
}

class _PricingInfoTab extends State<PricingInfoTab> {
  final WalletViewModel walletVM = WalletViewModel();
  DynamicPricingService? pricingService;
  bool isLoading = true;
  double maxCashAdvance = 3000.0; // Default max amount

  @override
  void initState() {
    super.initState();
    initialisePricingService();
    _fetchMaxCashAdvance();
  }

  Future<void> initialisePricingService() async {
    final service = await DynamicPricingService.initialize();
    setState(() {
      pricingService = service;
      isLoading = false;
    });
  }

  Future<void> _fetchMaxCashAdvance() async {
    double fetchedAmount = await walletVM.getMaxCashAdvanceAmount();
    setState(() {
      maxCashAdvance = fetchedAmount;
    });
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

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

            SizedBox(height: SizeConfig.heightMultiplier * 3),

            // 🟢 Section 2: Top-Up Pricing
            if (FeatureFlags.enableTopUpPaystack) ...[
              _sectionTitle('Top-Up Pricing'),
              _buildBulletPoint(
                  '🔹 Instant top-ups via Paystack (Card, Bank Transfer, Mobile Money).'),
              SizedBox(height: SizeConfig.heightMultiplier * 1),
              _pricingRow('💳 Card Payment', '2.5% + R1.00'),
              _pricingRow('🏦 Bank Transfer', '1.8%'),
              _pricingRow('📲 Mobile Money', '3%'),
              SizedBox(height: SizeConfig.heightMultiplier * 3),
            ],

            // 🟢 Section 3: Cash Advance (Dynamic)
            if (FeatureFlags.enableCashAdvance)
              FutureBuilder(
                future: Future.wait([
                  FeesConfig.getMaxCashAdvanceAmount(),
                  FeesConfig.getAdvanceFee(),
                  FeesConfig.getBankFee(),
                  FeesConfig.getRepaymentTerm(),
                ]),
                builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator(); // or SizedBox.shrink()
                  }

                  final double maxAdvance = snapshot.data![0];
                  final double advanceFee = snapshot.data![1];
                  final double bankFee = snapshot.data![2];
                  final String repaymentTerm = snapshot.data![3];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _sectionTitle('Cash Advance'),
                      _buildBulletPoint(
                          '💰 Borrow funds instantly & repay in $repaymentTerm.'),
                      _buildBulletPoint(
                          '📅 ${advanceFee.toStringAsFixed(0)}% fee applies for the $repaymentTerm advance.'),

                      _pricingRow('Minimum Advance', 'R100'),
                      _pricingRow('Maximum Advance',
                          'R${maxAdvance.toStringAsFixed(0)}'),
                      _pricingRow(
                          'Flat Fee', '${advanceFee.toStringAsFixed(0)}%'),
                      _pricingRow(
                          'Bank Transfer', '${bankFee.toStringAsFixed(0)}%'),
                      _pricingRow('Repayment Period', repaymentTerm),
                      _pricingRow('Instant Payment fee between banks',
                          'R50'), // Hardcoded if not dynamic

                      SizedBox(height: SizeConfig.heightMultiplier * 3),
                    ],
                  );
                },
              ),

            // 🟢 Section 4: Payouts (Dynamic)
            if (FeatureFlags.enableBalancePayout) ...[
              _sectionTitle('Payouts'),
              _buildBulletPoint(
                  '🕒 Request anytime - Processed during business hours.'),
              _buildBulletPoint('🔍 Track payout status in real-time.'),
              _buildBulletPoint('🏧 Funds sent to your linked bank account.'),
              SizedBox(height: SizeConfig.heightMultiplier * 3),
            ],

            // 🟢 Section 5: Messaging Pricing & Fees
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

            // 🟢 Section 6: Need Help?
            _sectionTitle('Need Help?'),
            _helpOption('0648370009'),
          ],
        ),
      ),
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
