import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promotions/widgets/create_template/force_boilerplate.dart';

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
          .replaceAll('{{customerName}}', 'Sibusiso')
          .replaceAll('{{shopName}}', shopName);
    }

    Widget buildMessageCard({
      required String messageContent,
      String? mediaUrl,
    }) {
      return Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mediaUrl != null && mediaUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                child: Image.network(
                  mediaUrl,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                messageContent,
                style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.8, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
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
                const Icon(Icons.info_outline, color: Colors.orange),
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
        Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text('Template Name: $templateName',
              style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 2.5,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: SizeConfig.heightMultiplier * 1),
        ]),
        if (includeWhatsApp)
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('WhatsApp Message Preview',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'WhatsApp Cost: R${whatsappPrice!.toStringAsFixed(2)} per recipient'),
              buildMessageCard(
                messageContent: resolvedMessage(
                    forceBoilerplate(whatsappContent), shopName),
                mediaUrl: mediaUrl,
              ),
            ],
          ),
        if (includeSMS)
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('SMS Message Preview',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'SMS Cost: R${(smsSegments * smsPricePerSegment!).toStringAsFixed(2)} per recipient'),
              buildMessageCard(
                messageContent: resolvedMessage(smsContent, shopName),
              ),
            ],
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            const Divider(),
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
