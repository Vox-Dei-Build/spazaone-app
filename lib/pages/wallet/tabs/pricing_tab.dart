import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/utils/support_util.dart';
import 'package:pasella/config/size_config.dart';

/// Billing > Account > Fees and limits page.
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
  RemoteConfigService? remoteConfigService;
  Object? pricingError;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialisePricingService();
  }

  Future<void> _initialisePricingService() async {
    try {
      final remoteConfig = await RemoteConfigService.getInstance();
      final service = await DynamicPricingService.initialize();
      if (!mounted) return;
      setState(() {
        remoteConfigService = remoteConfig;
        pricingService = service;
        pricingError = null;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        pricingError = error;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final rc = remoteConfigService;
    final localPercent = rc?.getDouble(
          'PAYSTACK_LOCAL_PERCENT',
          defaultValue: 2.9,
        ) ??
        2.9;
    final localFlat =
        rc?.getDouble('PAYSTACK_LOCAL_FLAT', defaultValue: 1) ?? 1;
    final eftPercent =
        rc?.getDouble('PAYSTACK_EFT_PERCENT', defaultValue: 2) ?? 2;
    final intPercent =
        rc?.getDouble('PAYSTACK_INT_PERCENT', defaultValue: 3.1) ?? 3.1;
    final intFlat = rc?.getDouble('PAYSTACK_INT_FLAT', defaultValue: 1) ?? 1;
    final transferFee =
        rc?.getDouble('PAYSTACK_TRANSFER_FEE', defaultValue: 3) ?? 3;
    final vatPercent =
        rc?.getDouble('PAYSTACK_VAT_PERCENT', defaultValue: 15) ?? 15;

    // Per-segment SMS rates and per-message WhatsApp rates. See
    // dynamic_pricing_service.dart for the underlying Remote Config
    // keys and markup model.
    final smsReminderRate = pricingService?.smsReminderTemplatePrice;
    final smsPaymentRate = pricingService?.smsPaymentTemplatePrice;
    final whatsappUtilityRate = pricingService?.whatsappUtilityPrice;
    final whatsappPromotionRate = pricingService?.whatsappPromotionPrice;

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
            // Messaging
            // -----------------------------------------------------------
            if (FeatureFlags.enablePricingInfo) ...[
              _sectionTitle('Customer messages'),
              _buildBulletPoint(
                'You see the full estimated cost before sending.',
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 2),
              if (pricingError != null ||
                  smsReminderRate == null ||
                  smsPaymentRate == null ||
                  whatsappUtilityRate == null ||
                  whatsappPromotionRate == null)
                _pricingUnavailable()
              else
                _messagePricingCard(
                  smsCustomerRate: smsReminderRate,
                  smsPaymentRate: smsPaymentRate,
                  whatsappUtilityRate: whatsappUtilityRate,
                  whatsappPromotionRate: whatsappPromotionRate,
                ),
              _sectionGap(),
            ],

            // -----------------------------------------------------------
            // Order payments
            // -----------------------------------------------------------
            if (FeatureFlags.enablePricingInfo) ...[
              _sectionTitle('Order payments'),
              _buildBulletPoint(
                'Cash orders have no online payment fee. Online orders include '
                'the payment fee shown before checkout.',
              ),
              _sectionGap(),
            ],

            // -----------------------------------------------------------
            // Paystack
            // -----------------------------------------------------------
            if (FeatureFlags.enablePricingInfo &&
                FeatureFlags.enableTopUpPaystack) ...[
              _sectionTitle('Payment fees (South Africa)'),
              _buildBulletPoint(
                'Local payments: ${localPercent.toStringAsFixed(1)}% + '
                '${CurrencyUtil.format(localFlat)} (excl. VAT)',
              ),
              _buildBulletPoint(
                'Bank EFT: ${eftPercent.toStringAsFixed(1)}% (excl. VAT)',
              ),
              _buildBulletPoint(
                'International payments: ${intPercent.toStringAsFixed(1)}% + '
                '${CurrencyUtil.format(intFlat)} (excl. VAT)',
              ),
              _buildBulletPoint(
                'Automatic online sales payouts are free. Outbound bank '
                'transfers initiated through the payment provider cost '
                '${CurrencyUtil.format(transferFee)} (excl. VAT)',
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
            '${CurrencyUtil.format(sale)} = ${CurrencyUtil.format(base)}',
          ),
          if (flat > 0)
            _exampleLine(
              'Flat fee: ${CurrencyUtil.format(flat)} → '
              'subtotal ${CurrencyUtil.format(subtotal)}',
            ),
          _exampleLine(
            'VAT: ${vat.toStringAsFixed(0)}% of '
            '${CurrencyUtil.format(subtotal)} = ${CurrencyUtil.format(vatAmount)}',
          ),
          _exampleLine('Total fee: ${CurrencyUtil.format(total)}'),
          _exampleLine(
            'Merchant receives: ${CurrencyUtil.format(merchant)}',
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

  Widget _messagePricingCard({
    required double smsCustomerRate,
    required double smsPaymentRate,
    required double whatsappUtilityRate,
    required double whatsappPromotionRate,
  }) {
    return MessagingPricingSummary(
      smsCustomerRate: smsCustomerRate,
      smsPaymentRate: smsPaymentRate,
      whatsappUtilityRate: whatsappUtilityRate,
      whatsappPromotionRate: whatsappPromotionRate,
    );
  }

  Widget _pricingUnavailable() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('messaging-pricing-unavailable'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pricing temporarily unavailable',
            style: TextStyle(
              color: colors.onErrorContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Paid messages remain unavailable until current pricing is '
            'confirmed.',
            style: TextStyle(color: colors.onErrorContainer),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  isLoading = true;
                  pricingError = null;
                });
                _initialisePricingService();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
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
      onPressed: () => SupportUtil.sendWhatsAppMessage(
        context,
        WhatsAppMessageType.support,
      ),
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

class MessagingPricingSummary extends StatelessWidget {
  const MessagingPricingSummary({
    super.key,
    required this.smsCustomerRate,
    required this.smsPaymentRate,
    required this.whatsappUtilityRate,
    required this.whatsappPromotionRate,
  });

  final double smsCustomerRate;
  final double smsPaymentRate;
  final double whatsappUtilityRate;
  final double whatsappPromotionRate;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('messaging-pricing-available'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            _MessagingRateRow(
              title: 'WhatsApp customer updates',
              rate: whatsappUtilityRate,
              unit: 'per customer',
            ),
            const Divider(),
            _MessagingRateRow(
              title: 'WhatsApp promotions',
              rate: whatsappPromotionRate,
              unit: 'per customer',
            ),
            const Divider(),
            _MessagingRateRow(
              title: 'SMS customer messages',
              rate: smsCustomerRate,
              unit: 'per SMS part',
            ),
            const Divider(),
            _MessagingRateRow(
              title: 'SMS payment confirmations',
              rate: smsPaymentRate,
              unit: 'per SMS part',
            ),
            const Divider(height: 1),
            const ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.only(bottom: 12),
              title: Text(
                'How SMS parts work',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              children: [
                Text(
                  'A longer SMS, or one containing emoji and some special '
                  'characters, can use more than one part. The app calculates '
                  'the total after customer and shop details are added.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagingRateRow extends StatelessWidget {
  const _MessagingRateRow({
    required this.title,
    required this.rate,
    required this.unit,
  });

  final String title;
  final double rate;
  final String unit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title)),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyUtil.format(rate),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(unit, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      );
}
