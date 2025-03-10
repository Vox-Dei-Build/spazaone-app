import 'package:pasella/config/remote_config.dart';

class DynamicPricingService {
  final RemoteConfigService remoteConfigService;

  DynamicPricingService(this.remoteConfigService);

  static Future<DynamicPricingService> initialize() async {
    final remoteConfigService = await RemoteConfigService.getInstance();

    return DynamicPricingService(remoteConfigService);
  }

  double calculatePrice(String usdPriceKey, String markupPercentageKey) {
    final usdPrice = double.parse(remoteConfigService.getString(usdPriceKey));
    final markupPercent =
        double.parse(remoteConfigService.getString(markupPercentageKey));
    final double exchangeRate =
        double.parse(remoteConfigService.getString('USD_ZAR_EXCHANGE_RATE'));

    final zarBase = usdPrice * exchangeRate;
    final finalPrice = zarBase + (zarBase * markupPercent / 100);

    return double.parse(finalPrice.toStringAsFixed(2));
  }

  double get smsReminderTemplatePrice =>
      calculatePrice('USD_SMS_REMINDER_PRICE', 'MARKUP_SMS_PERCENTAGE');
  double get smsPaymentTemplatePrice =>
      calculatePrice('USD_SMS_PAYMENT_PRICE', 'MARKUP_SMS_PERCENTAGE');
  double get whatsappUtilityPrice => calculatePrice(
      'USD_WHATSAPP_UTILITY_PRICE', 'MARKUP_WHATSAPP_PERCENTAGE');
  double get whatsappPromotionPrice => calculatePrice(
      'USD_WHATSAPP_PROMOTIONAL_PRICE', 'MARKUP_PROMOTIONAL_PERCENTAGE');
}
