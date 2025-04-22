import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/widgets/message_preview_card.dart';
import 'package:pasella/pages/promote/widgets/promotions/recepients.dart';

class ReviewAndPricingStep extends StatelessWidget {
  final String? templateContent;
  final String? mediaUrl;
  final String shopName;
  final bool sendWhatsApp;
  final bool sendSMS;
  final double totalCost;
  final Map<String, dynamic> breakdown;

  /// Optional list of all customers and the set of IDs selected for this promotion.
  final List<Map<String, dynamic>>? customers;
  final Set<String>? selectedCustomerIds;

  const ReviewAndPricingStep({
    Key? key,
    required this.templateContent,
    required this.mediaUrl,
    required this.shopName,
    required this.sendWhatsApp,
    required this.sendSMS,
    required this.totalCost,
    required this.breakdown,
    this.customers,
    this.selectedCustomerIds,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final resolved = templateContent
            ?.replaceAll('{{customerName}}', '[Customer Name]')
            .replaceAll('{{shopName}}', shopName) ??
        'No preview available';

    // ─── Null‑safe unpacking ──────────────────────────
    final int whatsappCount = (breakdown['whatsappCount'] as int?) ?? 0;
    final double whatsappUnit =
        (breakdown['whatsappUnit'] as num?)?.toDouble() ?? 0.0;

    final int smsCount = (breakdown['smsCount'] as int?) ?? 0;
    final double smsUnit = (breakdown['smsUnit'] as num?)?.toDouble() ?? 0.0;
    final int smsSegments = (breakdown['smsSegments'] as int?) ?? 1;
    // ─────────────────────────────────────────────────

    return SingleChildScrollView(
      padding: LayoutConstants.padding10Horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // WhatsApp block
          if (sendWhatsApp) ...[
            Text(
              "WhatsApp Preview",
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.8,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              "$whatsappCount via WhatsApp @ "
              "R${whatsappUnit.toStringAsFixed(2)} = "
              "R${(whatsappCount * whatsappUnit).toStringAsFixed(2)}",
              textAlign: TextAlign.center,
            ),
            MessagePreviewCard(
              content: resolved,
              mediaUrl: mediaUrl,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
          ],

          // SMS block
          if (sendSMS) ...[
            Text(
              "SMS Preview",
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.8,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              "$smsCount via SMS @ "
              "R${smsUnit.toStringAsFixed(2)} × $smsSegments = "
              "R${(smsCount * smsUnit * smsSegments).toStringAsFixed(2)}",
              textAlign: TextAlign.center,
            ),
            MessagePreviewCard(content: resolved),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
          ],

          // Recipients list (shrink‑wrapped inside)
          if (customers != null && selectedCustomerIds != null) ...[
            SelectedCustomersRecipients(
              customers: customers!,
              selectedCustomerIds: selectedCustomerIds!,
              onCustomerTap: (customer) {/* … */},
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
          ],

          const Divider(color: Colors.grey),

          // Total
          Text(
            "Total: R${totalCost.toStringAsFixed(2)}",
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 2,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
