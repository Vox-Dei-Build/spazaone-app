import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/promotions_page.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/message_preview_card.dart';
import 'package:pasella/pages/promote/widgets/confirmation_dialog.dart';
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
        .replaceAll('{{customerName}}', '[Customer Name]')
        .replaceAll('{{shopName}}', shopName);
  }

  @override
  Widget build(BuildContext context) {
    final name = template['name'] ?? 'Untitled';
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
        title: 'Template: $name',
        trailing: IconButton(
          icon: Icon(Icons.delete, size: SizeConfig.imageSizeMultiplier * 5),
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => ConfirmationDialog(
                title: 'Delete Template',
                message: 'Are you sure you want to delete this template?',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                onConfirm: () async {
                  final success =
                      await viewModel.deleteTemplate(templateId, template);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? 'Template deleted successfully'
                          : 'Failed to delete template'),
                    ),
                  );
                  if (success) {
                    Navigator.pushReplacementNamed(context, PromotionsPage.id);
                  }
                },
              ),
            );
          },
        ),
      ),
      body: ListView(
        padding: LayoutConstants.padding10Horizontal,
        children: [
          Text("Created: $formattedDate", textAlign: TextAlign.center),
          SizedBox(height: SizeConfig.heightMultiplier * 2),
          if (whatsapp != null) ...[
            const Text('WhatsApp Preview',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
                'WhatsApp Cost: R${whatsappPrice!.toStringAsFixed(2)} per recipient',
                textAlign: TextAlign.center),
            MessagePreviewCard(
              content: resolvedMessage(whatsapp['templateContent']),
              mediaUrl: whatsapp['mediaUrl'],
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 4),
          ],
          if (sms != null) ...[
            const Text('SMS Preview',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'SMS Cost: R${(smsSegments * smsPricePerSegment!).toStringAsFixed(2)} per recipient',
              textAlign: TextAlign.center,
            ),
            MessagePreviewCard(
              content: resolvedMessage(sms['templateContent']),
            ),
          ],
        ],
      ),
    );
  }
}
