import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/widgets/message_preview_card.dart';

class TemplateAndDetailsStep extends StatelessWidget {
  final String? selectedTemplateId;
  final ValueChanged<String?> onTemplateChanged;
  final bool sendWhatsApp;
  final bool sendSMS;
  final ValueChanged<bool> onWhatsAppChanged;
  final ValueChanged<bool> onSMSChanged;
  final List<Map<String, dynamic>> templates;
  final String shopName;
  final double? whatsappPrice;
  final double? smsPricePerSegment;

  const TemplateAndDetailsStep({
    super.key,
    required this.selectedTemplateId,
    required this.onTemplateChanged,
    required this.sendWhatsApp,
    required this.sendSMS,
    required this.onWhatsAppChanged,
    required this.onSMSChanged,
    required this.templates,
    required this.shopName,
    required this.whatsappPrice,
    required this.smsPricePerSegment,
  });

  @override
  Widget build(BuildContext context) {
    final selected = templates.firstWhere(
      (t) => t['id'] == selectedTemplateId,
      orElse: () => {},
    );

    final content = selected['channels']?['whatsapp']?['templateContent'];
    final hasPreview = content is String && content.isNotEmpty;
    final mediaUrl = selected['channels']?['whatsapp']?['mediaUrl'];
    final smsSegments =
        content != null ? ((content as String).length / 160).ceil() : 1;

    final preview = hasPreview
        ? content
            .replaceAll('{{customerName}}', '[Customer Name]')
            .replaceAll('{{shopName}}', shopName)
        : 'No preview available for this template.';

    return ListView(
      padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 4,
          vertical: SizeConfig.heightMultiplier * 1),
      children: [
        Text(
          "Choose a Template",
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        DropdownButtonFormField<String>(
          value: selectedTemplateId,
          isExpanded: true,
          items: templates.map((template) {
            final name = template['name'] ?? 'Untitled';
            return DropdownMenuItem<String>(
              value: template['id'],
              child: Text(name, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: onTemplateChanged,
          decoration: InputDecoration(
            hintText: 'Select a template',
            border: const OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
                horizontal: SizeConfig.imageSizeMultiplier * 1,
                vertical: SizeConfig.heightMultiplier * 1),
          ),
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        Text(
          "Choose Channels",
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 1),
        CheckboxListTile(
          value: sendWhatsApp,
          onChanged: (val) => onWhatsAppChanged(val ?? false),
          title: const Text("WhatsApp"),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          value: sendSMS,
          onChanged: (val) => onSMSChanged(val ?? false),
          title: const Text("SMS"),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        Divider(
          color: Colors.grey,
          thickness: SizeConfig.heightMultiplier * 0,
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        if (sendWhatsApp)
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('WhatsApp Preview',
                  style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 2,
                      fontWeight: FontWeight.bold)),
              if (selectedTemplateId != null)
                Text(
                    'WhatsApp Cost: R${whatsappPrice!.toStringAsFixed(2)} per recipient'),
              MessagePreviewCard(
                content: preview,
                mediaUrl: mediaUrl,
              ),
              Divider(
                color: Colors.grey,
                thickness: SizeConfig.heightMultiplier * 0,
              ),
            ],
          ),
        if (sendSMS)
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('SMS Preview',
                  style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 2,
                      fontWeight: FontWeight.bold)),
              if (selectedTemplateId != null)
                Text(
                    'SMS Cost: R${(smsSegments * smsPricePerSegment!).toStringAsFixed(2)} per recipient'),
              MessagePreviewCard(
                content: preview,
              ),
            ],
          ),
      ],
    );
  }
}
