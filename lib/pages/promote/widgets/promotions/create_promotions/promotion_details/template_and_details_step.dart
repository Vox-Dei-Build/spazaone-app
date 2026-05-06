import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/widgets/message_preview_card.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

class TemplateAndDetailsStep extends StatefulWidget {
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
  State<TemplateAndDetailsStep> createState() => _TemplateAndDetailsStepState();
}

class _TemplateAndDetailsStepState extends State<TemplateAndDetailsStep> {
  late List<Map<String, dynamic>> approvedTemplates;

  @override
  void initState() {
    super.initState();
    approvedTemplates = widget.templates
        .where((t) => t['channels']?['whatsapp']?['approved'] == true)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final selected = approvedTemplates.firstWhere(
      (t) => t['id'] == widget.selectedTemplateId,
      orElse: () => {},
    );

    final content = selected['channels']?['whatsapp']?['templateContent'];
    final hasPreview = content is String && content.isNotEmpty;
    final mediaUrl = selected['channels']?['whatsapp']?['mediaUrl'];
    final smsSegments = content is String && content.isNotEmpty
        ? SMSPricingUtil.calculateSegments(content)
        : 1;

    final preview = hasPreview
        ? content
            .replaceAll('{{customerName}}', '[Customer Name]')
            .replaceAll('{{shopName}}', widget.shopName)
        : 'No preview available for this template.';

    final hasTemplates = approvedTemplates.isNotEmpty;

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 4,
        vertical: SizeConfig.heightMultiplier * 1,
      ),
      children: [
        Text("Choose a Template",
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        DropdownButtonFormField<String>(
          value: widget.selectedTemplateId,
          isExpanded: true,
          items: hasTemplates
              ? approvedTemplates.map((template) {
                  final name = template['name'] ?? 'Untitled';
                  return DropdownMenuItem<String>(
                    value: template['id'],
                    child: Text(name, overflow: TextOverflow.ellipsis),
                  );
                }).toList()
              : [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text("No approved templates",
                        style: TextStyle(color: Colors.grey)),
                  )
                ],
          onChanged: hasTemplates ? widget.onTemplateChanged : null,
          decoration: InputDecoration(
            hintText: hasTemplates ? 'Select a template' : '—',
            border: const OutlineInputBorder(),
            // …
          ),
        ),
        if (!hasTemplates)
          Padding(
            padding: EdgeInsets.only(top: SizeConfig.heightMultiplier * 2),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                Expanded(
                  child: Text(
                    "You need at least one approved template before running a promotion. "
                    "Head to the “Templates” tab to create and approve one.",
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: SizeConfig.textMultiplier * 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        Text("Choose Channels",
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        SizedBox(height: SizeConfig.heightMultiplier * 1),
        CheckboxListTile(
          value: widget.sendWhatsApp,
          onChanged: hasTemplates
              ? (val) => widget.onWhatsAppChanged(val ?? false)
              : null,
          title: const Text("WhatsApp"),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          value: widget.sendSMS,
          onChanged:
              hasTemplates ? (val) => widget.onSMSChanged(val ?? false) : null,
          title: const Text("SMS"),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        Divider(color: Colors.grey, thickness: SizeConfig.heightMultiplier * 0),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        if (widget.sendWhatsApp)
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('WhatsApp Preview',
                  style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 2,
                      fontWeight: FontWeight.bold)),
              if (widget.selectedTemplateId != null)
                Text(
                    'WhatsApp Cost: R${widget.whatsappPrice!.toStringAsFixed(2)} per recipient'),
              MessagePreviewCard(content: preview, mediaUrl: mediaUrl),
              Divider(
                  color: Colors.grey,
                  thickness: SizeConfig.heightMultiplier * 0),
            ],
          ),
        if (widget.sendSMS)
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('SMS Preview',
                  style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 2,
                      fontWeight: FontWeight.bold)),
              if (widget.selectedTemplateId != null)
                Text(
                    'SMS Cost: $smsSegments segment${smsSegments == 1 ? '' : 's'} × R${widget.smsPricePerSegment!.toStringAsFixed(2)} = R${(smsSegments * widget.smsPricePerSegment!).toStringAsFixed(2)} per recipient'),
              MessagePreviewCard(content: preview),
            ],
          ),
      ],
    );
  }
}
