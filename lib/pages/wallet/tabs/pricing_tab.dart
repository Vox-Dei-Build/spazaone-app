import 'package:flutter/material.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/feature_flags.dart';
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

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 🟢 Section 1: How It Works
            _sectionTitle('How It Works'),
            if (FeatureFlags.enableBalancePayout) ...[
              _buildBulletPoint(
                  '📌 Account setup - Add your banking details to receive payouts.'),
              _buildBulletPoint(
                  '💰 Request payouts - Withdraw your balance at any time.'),
            ],

            _buildBulletPoint(
                '📊 Viewing balance - Your balance is visible at the top of the wallet page.'),

            _buildBulletPoint(
                '📜 Transaction history - Track payments & expenses in the History tab.'),

            SizedBox(height: SizeConfig.heightMultiplier * 3),

            // 🟢 Section 2: Top-Up Pricing
            _sectionTitle('Top-Up Pricing'),
            _buildBulletPoint(
                '🔹 Top-up via Paystack - Instant wallet top-ups using card, bank transfer, or mobile money.'),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            _pricingRow('💳 Card Payment', '2.5% + R1.00'),
            _pricingRow('🏦 Bank Transfer', '1.8%'),
            _pricingRow('📲 Mobile Money', '3%'),

            SizedBox(height: SizeConfig.heightMultiplier * 3),

            // 🟢 Section 3: Messaging Pricing & Fees
            _sectionTitle('Messaging Pricing & Fees'),
            _buildBulletPoint(
                '💬 Pricing is usage-based, meaning you are charged per message sent.'),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            _pricingRow('Reminder SMS',
                '${CurrencyUtil.format(pricingService?.smsReminderTemplatePrice ?? 0)}/Msg'),
            _pricingRow('WhatsApp Reminder',
                '${CurrencyUtil.format(pricingService?.whatsappUtilityPrice ?? 0)}/Msg'),
            _divider(),
            _pricingRow('Credit SMS',
                '${CurrencyUtil.format(pricingService?.smsReminderTemplatePrice ?? 0)}/Msg'),
            _pricingRow('WhatsApp Credit',
                '${CurrencyUtil.format(pricingService?.whatsappUtilityPrice ?? 0)}/Msg'),
            _divider(),
            _pricingRow('Payment SMS',
                '${CurrencyUtil.format(pricingService?.smsPaymentTemplatePrice ?? 0)}/Msg'),
            _pricingRow('WhatsApp Payment',
                '${CurrencyUtil.format(pricingService?.whatsappUtilityPrice ?? 0)}/Msg'),
            _divider(),
            _pricingRow('Onboarding SMS',
                '${CurrencyUtil.format(pricingService?.smsReminderTemplatePrice ?? 0)}/Msg'),
            _pricingRow('WhatsApp Onboarding',
                '${CurrencyUtil.format(pricingService?.whatsappUtilityPrice ?? 0)}/Msg'),
            _divider(),
            _pricingRow('WhatsApp Promotions',
                '${CurrencyUtil.format(pricingService?.whatsappPromotionPrice ?? 0)}/Msg'),
            _pricingRow('AI Assistant', 'R0.25/Msg'),

            SizedBox(height: SizeConfig.heightMultiplier * 3),

            // 🟢 Section 4: Cash Advance
            if (FeatureFlags.enableCashAdvance) ...[
              _sectionTitle('Cash Advance'),
              _buildBulletPoint(
                  '💰 Borrow funds instantly and repay in 7 days.'),
              _buildBulletPoint('📅 10% fee applies for the 7-day advance.'),
              _pricingRow('Minimum Advance', 'R100'),
              _pricingRow('Maximum Advance', 'R1,000'),
              _pricingRow('Flat Fee', '10%'),
              _pricingRow('Repayment Period', '7 Days'),
              SizedBox(height: SizeConfig.heightMultiplier * 3)
            ],

            // 🟢 Section 5: Payouts
            if (FeatureFlags.enableBalancePayout) ...[
              _sectionTitle('Payouts'),
              _buildBulletPoint(
                  '🕒 Request anytime - Processed during business hours.'),
              _buildBulletPoint(
                  '🔍 Status tracking - Get real-time payout updates.'),
              _buildBulletPoint(
                  '🏧 Direct deposits - Funds sent to your linked bank account.'),
              SizedBox(height: SizeConfig.heightMultiplier * 3),
            ],

            // 🟢 Section 6: Need Help?
            _sectionTitle('Need Help?'),
            _helpOption('💬 WhatsApp Us: 064 837 0009', '0648370009'),
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
            fontSize: SizeConfig.textMultiplier * 2.5,
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
          Text('',
              style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 3,
                  color: Colors.black54)),
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

  // ✅ WhatsApp Help Option with Clickable Link
  Widget _helpOption(String text, String phone) {
    return GestureDetector(
      onTap: () => _launchWhatsApp(phone),
      child: Padding(
        padding:
            EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 0.8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 2,
            color: Colors.blue,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  // ✅ Open WhatsApp Chat
  void _launchWhatsApp(String phone) async {
    final url = "https://wa.me/$phone";
    if (await canLaunch(url)) {
      await launch(url);
    }
  }
}
