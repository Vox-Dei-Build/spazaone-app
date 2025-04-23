import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/widgets/message_preview_card.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/force_boilerplate.dart';

class ReviewStep extends StatelessWidget {
  final String templateName;
  final String whatsappContent;
  final String smsContent;
  final String mediaUrl;
  final bool includeWhatsApp;
  final bool includeSMS;
  final double? whatsappPrice;
  final double? smsPricePerSegment;
  final int smsSegments;
  final String shopName;

  const ReviewStep({
    super.key,
    required this.templateName,
    required this.whatsappContent,
    required this.smsContent,
    required this.mediaUrl,
    required this.includeWhatsApp,
    required this.includeSMS,
    required this.whatsappPrice,
    required this.smsPricePerSegment,
    required this.smsSegments,
    required this.shopName,
  });

  @override
  Widget build(BuildContext context) {
    String resolvedMessage(String content, String shopName) {
      return content
          .replaceAll('{{customerName}}', '[Customer Name]')
          .replaceAll('{{shopName}}', shopName);
    }

    return ListView(
      padding:
          EdgeInsets.symmetric(horizontal: SizeConfig.imageSizeMultiplier * 1),
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text('Name: $templateName',
              style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 2,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: SizeConfig.heightMultiplier * 1),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.orange,
                  size: SizeConfig.textMultiplier * 1.8,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Once a template is created, it cannot be edited. Please create a new one if changes are needed.',
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.6,
                      color: Colors.orange.shade900,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(
          color: Colors.grey,
          thickness: SizeConfig.heightMultiplier * 0,
        ),
        if (includeWhatsApp)
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('WhatsApp Preview',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'WhatsApp Cost: R${whatsappPrice!.toStringAsFixed(2)} per recipient'),
              MessagePreviewCard(
                content: resolvedMessage(
                    forceBoilerplate(whatsappContent), shopName),
                mediaUrl: mediaUrl,
              ),
              Divider(
                color: Colors.grey,
                thickness: SizeConfig.heightMultiplier * 0,
              ),
            ],
          ),
        if (includeSMS)
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('SMS Preview',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'SMS Cost: R${(smsSegments * smsPricePerSegment!).toStringAsFixed(2)} per recipient'),
              MessagePreviewCard(
                content: resolvedMessage(smsContent, shopName),
              ),
            ],
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            Divider(
              color: Colors.grey,
              thickness: SizeConfig.heightMultiplier * 0,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            if (includeWhatsApp)
              Text(
                  'WhatsApp Cost: R${whatsappPrice!.toStringAsFixed(2)} per recipient'),
            if (includeSMS)
              Text(
                  'SMS Cost: R${(smsSegments * smsPricePerSegment!).toStringAsFixed(2)} per recipient'),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
          ],
        ),
      ],
    );
  }
}
