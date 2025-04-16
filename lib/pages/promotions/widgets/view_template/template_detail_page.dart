import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promotions/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promotions/widgets/view_template/delete_confirmation_dialog.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';

class TemplateDetailPage extends StatelessWidget {
  final PromotionsViewModel viewModel;
  final Map<String, dynamic> template;
  final String shopName;
  final double? whatsappPrice;
  final double? smsPricePerSegment;

  const TemplateDetailPage({
    Key? key,
    required this.viewModel,
    required this.template,
    required this.shopName,
    required this.whatsappPrice,
    required this.smsPricePerSegment,
  }) : super(key: key);

  String resolvedMessage(String content) {
    return content
        .replaceAll('{{customerName}}', 'Sibusiso')
        .replaceAll('{{shopName}}', shopName);
  }

  Widget buildMessageCard({required String content, String? mediaUrl}) {
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
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image, size: 100),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              content,
              style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.8, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = template['name'] ?? 'Untitled';
    final contentType = template['contentType'] ?? 'Unknown';
    final channels = template['channels'] as Map<String, dynamic>? ?? {};
    final createdAt = template['createdAt']?.toDate();
    final formattedDate = createdAt != null
        ? DateFormat('MMM dd, yyyy – hh:mm a').format(createdAt)
        : "Unknown";

    final whatsapp = channels['whatsapp'] as Map<String, dynamic>?;
    final sms = channels['sms'] as Map<String, dynamic>?;
    final templateId = template['id'];

    final smsSegments = sms != null
        ? ((sms['templateContent'] as String).length / 160).ceil()
        : 1;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Template: ' + name,
        trailing: IconButton(
          icon: Icon(Icons.delete, size: SizeConfig.imageSizeMultiplier * 5),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) {
                return DeleteConfirmationDialog(
                  onConfirm: () async {
                    await viewModel.deleteTemplate(
                        context, templateId, template);
                    Navigator.pop(context); // Go back after deleting
                  },
                );
              },
            );
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        children: [
          Text("Type: $contentType", textAlign: TextAlign.center),
          Text("Created: $formattedDate", textAlign: TextAlign.center),
          SizedBox(height: SizeConfig.heightMultiplier * 2),
          if (whatsapp != null) ...[
            const Text('WhatsApp Message Preview',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
                'WhatsApp Cost: R${whatsappPrice!.toStringAsFixed(2)} per recipient',
                textAlign: TextAlign.center),
            buildMessageCard(
              content: resolvedMessage(whatsapp['templateContent']),
              mediaUrl: whatsapp['mediaUrl'],
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 4),
          ],
          if (sms != null) ...[
            const Text('SMS Message Preview',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'SMS Cost: R${(smsSegments * smsPricePerSegment!).toStringAsFixed(2)} per recipient',
              textAlign: TextAlign.center,
            ),
            buildMessageCard(
              content: resolvedMessage(sms['templateContent']),
            ),
          ],
        ],
      ),
    );
  }
}
