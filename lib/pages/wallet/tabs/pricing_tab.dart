import 'package:flutter/material.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/utils/currency_util.dart';

/// Plain-language, server-backed messaging and online-payment pricing.
class PricingInfoTab extends StatefulWidget {
  const PricingInfoTab({super.key});

  @override
  State<PricingInfoTab> createState() => _PricingInfoTabState();
}

class _PricingInfoTabState extends State<PricingInfoTab> {
  DynamicPricingService? _pricingService;
  RemoteConfigService? _remoteConfig;
  Object? _pricingError;
  bool _loading = true;
  int _selectedSection = 0;

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  Future<void> _loadPricing() async {
    try {
      final remoteConfig = await RemoteConfigService.getInstance();
      final pricing = await DynamicPricingService.initialize();
      if (!mounted) return;
      setState(() {
        _remoteConfig = remoteConfig;
        _pricingService = pricing;
        _pricingError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pricingError = error;
        _loading = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _pricingError = null;
    });
    _loadPricing();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _PricingSectionTabs(
          selectedIndex: _selectedSection,
          onSelected: (index) => setState(() => _selectedSection = index),
        ),
        Expanded(
          child: IndexedStack(
            index: _selectedSection,
            children: [
              _messageCosts(),
              _paymentCosts(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _messageCosts() {
    final pricing = _pricingService;
    final rates = pricing == null
        ? const <double>[]
        : <double>[
            pricing.smsReminderTemplatePrice,
            pricing.smsPaymentTemplatePrice,
            pricing.whatsappUtilityPrice,
            pricing.whatsappPromotionPrice,
          ];
    final ratesAvailable = _pricingError == null &&
        rates.length == 4 &&
        rates.every((rate) => rate > 0);

    return ListView(
      key: const ValueKey('messaging-costs-page'),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
      children: [
        Text(
          'Customer messages',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: kTertiaryColor,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 7),
        Text(
          'See what each message costs before you send it.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: kSecondaryAccent,
                height: 1.4,
              ),
        ),
        const SizedBox(height: 18),
        if (!ratesAvailable)
          _PricingUnavailable(onRetry: _retry)
        else
          MessagingPricingSummary(
            smsCustomerRate: rates[0],
            smsPaymentRate: rates[1],
            whatsappUtilityRate: rates[2],
            whatsappPromotionRate: rates[3],
          ),
      ],
    );
  }

  Widget _paymentCosts() {
    final config = _remoteConfig;
    if (_pricingError != null || config == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
        children: [_PricingUnavailable(onRetry: _retry)],
      );
    }

    final localPercent = config.getDouble(
      'PAYSTACK_LOCAL_PERCENT',
      defaultValue: 2.9,
    );
    final localFlat = config.getDouble(
      'PAYSTACK_LOCAL_FLAT',
      defaultValue: 1,
    );
    final eftPercent = config.getDouble(
      'PAYSTACK_EFT_PERCENT',
      defaultValue: 2,
    );
    final internationalPercent = config.getDouble(
      'PAYSTACK_INT_PERCENT',
      defaultValue: 3.1,
    );
    final internationalFlat = config.getDouble(
      'PAYSTACK_INT_FLAT',
      defaultValue: 1,
    );
    final vat = config.getDouble('PAYSTACK_VAT_PERCENT', defaultValue: 15);
    final valid = localPercent > 0 &&
        localFlat >= 0 &&
        eftPercent > 0 &&
        internationalPercent > 0 &&
        internationalFlat >= 0 &&
        vat > 0;

    return ListView(
      key: const ValueKey('online-payment-costs-page'),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
      children: [
        Text(
          'Online payments',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: kTertiaryColor,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 7),
        Text(
          'The exact fee is shown before a customer pays.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: kSecondaryAccent,
                height: 1.4,
              ),
        ),
        const SizedBox(height: 18),
        if (!valid)
          _PricingUnavailable(onRetry: _retry)
        else
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE4E7E5))),
            ),
            child: Column(
              children: [
                const _PricingRow(
                  title: 'Cash sales',
                  description: 'Recorded in SpazaOne',
                  value: 'No fee',
                ),
                _PricingRow(
                  title: 'Ozow (Instant EFT)',
                  description: 'South African bank payment',
                  value: '${eftPercent.toStringAsFixed(1)}% + VAT',
                ),
                _PricingRow(
                  title: 'Local card',
                  description: 'South African card',
                  value:
                      '${localPercent.toStringAsFixed(1)}% + ${CurrencyUtil.format(localFlat)} + VAT',
                ),
                _PricingRow(
                  title: 'International card',
                  description: 'Card issued outside South Africa',
                  value:
                      '${internationalPercent.toStringAsFixed(1)}% + ${CurrencyUtil.format(internationalFlat)} + VAT',
                ),
                _PricingRow(
                  title: 'VAT on payment fees',
                  description: 'Included when the final fee is calculated',
                  value: '${vat.toStringAsFixed(0)}%',
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PricingSectionTabs extends StatelessWidget {
  const _PricingSectionTabs({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE4E7E5))),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PricingTabButton(
              label: 'Messages',
              selected: selectedIndex == 0,
              onTap: () => onSelected(0),
            ),
          ),
          Expanded(
            child: _PricingTabButton(
              label: 'Online payments',
              selected: selectedIndex == 1,
              onTap: () => onSelected(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingTabButton extends StatelessWidget {
  const _PricingTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? kPrimaryColor : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? kPrimaryColor : kSecondaryAccent,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PricingUnavailable extends StatelessWidget {
  const _PricingUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('messaging-pricing-unavailable'),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Current prices could not load',
              style: TextStyle(
                color: colors.onErrorContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Try again before sending a paid message or taking an online payment.',
              style: TextStyle(color: colors.onErrorContainer, height: 1.4),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ),
          ],
        ),
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
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE4E7E5))),
      ),
      child: Column(
        children: [
          _PricingRow(
            title: 'WhatsApp customer updates',
            description: 'Receipts, reminders and order updates',
            value: CurrencyUtil.format(whatsappUtilityRate),
            unit: 'per customer',
          ),
          _PricingRow(
            title: 'WhatsApp promotions',
            description: 'Offers and marketing messages',
            value: CurrencyUtil.format(whatsappPromotionRate),
            unit: 'per customer',
          ),
          _PricingRow(
            title: 'SMS customer messages',
            description: 'A long SMS can use more than one part',
            value: CurrencyUtil.format(smsCustomerRate),
            unit: 'per SMS part',
          ),
          _PricingRow(
            title: 'SMS payment confirmations',
            description: 'A long SMS can use more than one part',
            value: CurrencyUtil.format(smsPaymentRate),
            unit: 'per SMS part',
          ),
        ],
      ),
    );
  }
}

class _PricingRow extends StatelessWidget {
  const _PricingRow({
    required this.title,
    required this.description,
    required this.value,
    this.unit,
  });

  final String title;
  final String description;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE4E7E5))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: kSecondaryAccent,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: kTertiaryColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    unit!,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: kSecondaryAccent,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
