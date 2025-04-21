import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/widgets/message_preview_card.dart';

class ReviewAndPricingStep extends StatelessWidget {
  final String? templateContent;
  final String? mediaUrl;
  final String shopName;
  final bool sendWhatsApp;
  final bool sendSMS;
  final double totalCost;
  final Map<String, dynamic> breakdown;

  const ReviewAndPricingStep({
    Key? key,
    required this.templateContent,
    required this.mediaUrl,
    required this.shopName,
    required this.sendWhatsApp,
    required this.sendSMS,
    required this.totalCost,
    required this.breakdown,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final resolved = templateContent
            ?.replaceAll('{{customerName}}', '[Customer Name]')
            .replaceAll('{{shopName}}', shopName) ??
        'No preview available';

    return ListView(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text("Estimated Cost",
                style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2,
                    fontWeight: FontWeight.bold)),
            Divider(
                thickness: SizeConfig.heightMultiplier * 0.0,
                color: Colors.grey),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            if (sendWhatsApp)
              Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text("Whatsapp Preview",
                    style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.8,
                        fontWeight: FontWeight.bold)),
                Text(
                  "${breakdown['whatsappCount']} via WhatsApp @ R${(breakdown['whatsappUnit'] as double).toStringAsFixed(2)} = R${(breakdown['whatsappCount'] * breakdown['whatsappUnit']).toStringAsFixed(2)}",
                ),
                MessagePreviewCard(
                  content: resolved,
                  mediaUrl: mediaUrl,
                ),
                Divider(
                    thickness: SizeConfig.heightMultiplier * 0.0,
                    color: Colors.grey),
                SizedBox(height: SizeConfig.heightMultiplier * 1),
              ]),
            if (sendSMS)
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text("SMS Preview",
                      style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 1.8,
                          fontWeight: FontWeight.bold)),
                  Text(
                    "${breakdown['smsCount']} via SMS @ R${(breakdown['smsUnit'] as double) * breakdown['smsSegments']} = R${(breakdown['smsCount'] * breakdown['smsUnit'] * breakdown['smsSegments']).toStringAsFixed(2)}",
                  ),
                  MessagePreviewCard(
                    content: resolved,
                  ),
                ],
              ),
            Divider(
                thickness: SizeConfig.heightMultiplier * 0.0,
                color: Colors.grey),
            Text(
              "Total: R${totalCost.toStringAsFixed(2)}",
              style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 2,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}
