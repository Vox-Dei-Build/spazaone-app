import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/utils/support_util.dart';
import 'package:pasella/config/size_config.dart';

/// Wallet > Account > Info segment.
///
/// This screen exists to honestly explain how the merchant is charged for
/// messaging and payments. The previous version misled users in three
/// concrete ways which this rewrite fixes:
///
///   1. SMS prices were labelled "/SMS" but the send path
///      ([SMSPricingUtil.calculateCost]) bills per 160-char (GSM-7) /
///      70-char (UCS-2) segment — long messages cost a multiple of the
///      displayed rate. Now labelled "/segment" with an explainer.
///   2. WhatsApp prices were labelled "/Msg" without explaining that
///      WhatsApp is billed once per recipient regardless of length and
///      that utility (transactional) and marketing (promotional) have
///      different rates. Both points are now spelled out.
///   3. A "WhatsApp AI Assistant — utilityPrice + R0.05" row was shown,
///      but no AI-assistant send path adds R0.05 anywhere in the
///      codebase. Row removed; can be re-introduced when an actual AI
///      send path with real billing exists.
///
/// Visual design: stripped of decorative emojis and FontAwesome icons.
/// Plain typographic hierarchy (section titles, body bullets, key/value
/// pricing rows, dividers) keeps the page scannable on small screens
/// without competing with the wallet's own iconography.
class PricingInfoTab extends StatefulWidget {
  const PricingInfoTab({super.key});

  @override
  State<PricingInfoTab> createState() => _PricingInfoTabState();
}

class _PricingInfoTabState extends State<PricingInfoTab> {
  DynamicPricingService? pricingService;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialisePricingService();
  }

  Future<void> _initialisePricingService() async {
    final service = await DynamicPricingService.initialize();
    if (!mounted) return;
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

    // Per-segment SMS rates and per-message WhatsApp rates. See
    // dynamic_pricing_service.dart for the underlying Remote Config
    // keys and markup model.
    final smsReminderRate = pricingService?.smsReminderTemplatePrice ?? 0;
    final smsPaymentRate = pricingService?.smsPaymentTemplatePrice ?? 0;
    final whatsappUtilityRate = pricingService?.whatsappUtilityPrice ?? 0;
    final whatsappPromotionRate = pricingService?.whatsappPromotionPrice ?? 0;

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.heightMultiplier * 2,
          vertical: SizeConfig.heightMultiplier * 2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // -----------------------------------------------------------
            // How it works
            // -----------------------------------------------------------
            _sectionTitle('How it works'),
            _buildBulletPoint(
              'Your wallet balance is always visible at the top of the wallet '
              'screen.',
            ),
            _buildBulletPoint(
              'Open Account > History to review every payment, top-up and '
              'message charge.',
            ),
            if (FeatureFlags.enableBalancePayout) ...[
              _buildBulletPoint(
                'Add banking details under Account > Banking to receive '
                'payouts.',
              ),
              _buildBulletPoint(
                'Request a payout at any time from the Withdraw tab.',
              ),
            ],
            _sectionGap(),

            // -----------------------------------------------------------
            // Payouts
            // -----------------------------------------------------------
            if (FeatureFlags.enableBalancePayout) ...[
              _sectionTitle('Payouts'),
              _buildBulletPoint(
                'Requests are processed during business hours.',
              ),
              _buildBulletPoint(
                'You can track payout status in real time on the Withdraw '
                'tab.',
              ),
              _buildBulletPoint(
                'Funds are transferred to your linked bank account.',
              ),
              _sectionGap(),
            ],

            // -----------------------------------------------------------
            // Messaging
            // -----------------------------------------------------------
            if (FeatureFlags.enablePricingInfo) ...[
              _sectionTitle('Messaging'),
              _buildBulletPoint(
                'WhatsApp messages are billed once per recipient regardless '
                'of length. Utility (transactional) and marketing rates '
                'differ — see the table below.',
              ),
              _buildBulletPoint(
                'SMS is billed per segment, not per message. A segment is '
                '160 characters of plain text, or 70 characters when the '
                'message contains emoji or special characters such as é, ô '
                'or curly quotes. Long messages may use multiple segments.',
              ),
              _buildBulletPoint(
                'The cost shown before sending is an estimate. The final '
                'charge is based on the rendered message — substituting '
                'longer customer or shop names can push the segment count '
                'up by one.',
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 2),

              // SMS rows. All transactional SMS templates share the
              // reminder rate at the moment (see
              // messaging_notification_service.dart line 392/439/468);
              // only Payment SMS uses the dedicated payment rate at
              // line 399. Onboarding and transaction confirmations are NOT shown as their
              // own rows because doing so falsely implies they have
              // independent rates.
              _pricingRowWithUnit(
                title: 'SMS — reminder, transaction, onboarding',
                rate: smsReminderRate,
                unit: 'per segment',
              ),
              _divider(),
              _pricingRowWithUnit(
                title: 'SMS — payment confirmation',
                rate: smsPaymentRate,
                unit: 'per segment',
              ),
              _divider(),
              _pricingRowWithUnit(
                title: 'SMS — promotions',
                rate: smsReminderRate,
                unit: 'per segment',
              ),
              _divider(),

              // WhatsApp rows.
              _pricingRowWithUnit(
                title: 'WhatsApp — transactional',
                rate: whatsappUtilityRate,
                unit: 'per message',
              ),
              _divider(),
              _pricingRowWithUnit(
                title: 'WhatsApp — promotions',
                rate: whatsappPromotionRate,
                unit: 'per message',
              ),
              _sectionGap(),
            ],

            // -----------------------------------------------------------
            // Order payments
            // -----------------------------------------------------------
            if (FeatureFlags.enablePricingInfo) ...[
              _sectionTitle('Order payments'),
              _buildBulletPoint(
                'Cash orders settle immediately with no platform fee.',
              ),
              _buildBulletPoint(
                'Online orders carry a platform fee plus the transaction '
                'fee charged by your payment provider.',
              ),
              _buildBulletPoint(
                'Wallet balance can be used for in-app purchases.',
              ),
              _sectionGap(),
            ],

            // -----------------------------------------------------------
            // Paystack
            // -----------------------------------------------------------
            if (FeatureFlags.enablePricingInfo &&
                FeatureFlags.enableTopUpPaystack) ...[
              _sectionTitle('Paystack fees (South Africa)'),
              _buildBulletPoint(
                'Local payments: ${localPercent.toStringAsFixed(1)}% + '
                'R${localFlat.toStringAsFixed(2)} (excl. VAT)',
              ),
              _buildBulletPoint(
                'Bank EFT: ${eftPercent.toStringAsFixed(1)}% (excl. VAT)',
              ),
              _buildBulletPoint(
                'International payments: ${intPercent.toStringAsFixed(1)}% + '
                'R${intFlat.toStringAsFixed(2)} (excl. VAT)',
              ),
              _buildBulletPoint(
                'Settlement (payouts): R${settlementFee.toStringAsFixed(2)} '
                'per transfer (excl. VAT)',
              ),
              _sectionGap(),
              _sectionTitle('Worked examples'),
              _exampleTransaction(
                title: 'Local card — R1 000 sale',
                sale: 1000,
                percent: localPercent,
                flat: localFlat,
                vat: vatPercent,
              ),
              _exampleTransaction(
                title: 'EFT — R1 000 sale',
                sale: 1000,
                percent: eftPercent,
                flat: 0,
                vat: vatPercent,
              ),
              _exampleTransaction(
                title: 'International card — R1 000 sale',
                sale: 1000,
                percent: intPercent,
                flat: intFlat,
                vat: vatPercent,
              ),
              _sectionGap(),
            ],

            // -----------------------------------------------------------
            // Help
            // -----------------------------------------------------------
            _sectionTitle('Need help?'),
            SizedBox(height: SizeConfig.heightMultiplier),
            _helpOption(),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
          ],
        ),
      ),
    );
  }

  Widget _exampleTransaction({
    required String title,
    required double sale,
    required double percent,
    required double flat,
    required double vat,
  }) {
    final base = sale * percent / 100;
    final subtotal = base + flat;
    final vatAmount = subtotal * vat / 100;
    final total = subtotal + vatAmount;
    final merchant = sale - total;

    return Padding(
      padding: EdgeInsets.only(bottom: SizeConfig.heightMultiplier * 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.7,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 0.5),
          _exampleLine(
            'Base fee: ${percent.toStringAsFixed(1)}% of '
            'R${sale.toStringAsFixed(0)} = R${base.toStringAsFixed(2)}',
          ),
          if (flat > 0)
            _exampleLine(
              'Flat fee: R${flat.toStringAsFixed(2)} → '
              'subtotal R${subtotal.toStringAsFixed(2)}',
            ),
          _exampleLine(
            'VAT: ${vat.toStringAsFixed(0)}% of '
            'R${subtotal.toStringAsFixed(2)} = R${vatAmount.toStringAsFixed(2)}',
          ),
          _exampleLine('Total fee: R${total.toStringAsFixed(2)}'),
          _exampleLine(
            'Merchant receives: R${merchant.toStringAsFixed(2)}',
            emphasised: true,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(
        top: SizeConfig.heightMultiplier * 0.5,
        bottom: SizeConfig.heightMultiplier * 1.2,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: SizeConfig.textMultiplier * 2.1,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _sectionGap() => SizedBox(height: SizeConfig.heightMultiplier * 3);

  Widget _divider() => Divider(
        thickness: 0.6,
        height: SizeConfig.heightMultiplier * 2,
        color: Colors.grey.shade300,
      );

  /// Body bullet — no leading glyph; the indentation and line spacing
  /// alone communicate list structure.
  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 0.5,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: SizeConfig.textMultiplier * 1.65,
          height: 1.4,
          color: Colors.black87,
        ),
      ),
    );
  }

  /// Pricing row that splits the unit ("per segment", "per message")
  /// onto a faint sub-line, so the price itself stays prominent.
  Widget _pricingRowWithUnit({
    required String title,
    required double rate,
    required String unit,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 0.5,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.65,
                color: Colors.black87,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyUtil.format(rate),
                style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.7,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              Text(
                unit,
                style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.3,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _exampleLine(String text, {bool emphasised = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 0.25,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: SizeConfig.textMultiplier * 1.55,
          color: emphasised ? Colors.black87 : Colors.black54,
          fontWeight: emphasised ? FontWeight.w600 : FontWeight.w400,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _helpOption() {
    return FilledButton.icon(
      onPressed: () =>
          SupportUtil.sendWhatsAppMessage(context, WhatsAppMessageType.support),
      icon: Icon(
        FontAwesomeIcons.whatsapp,
        size: SizeConfig.textMultiplier * 2,
      ),
      label: Text(
        'Chat to support',
        style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.8),
      ),
    );
  }
}
