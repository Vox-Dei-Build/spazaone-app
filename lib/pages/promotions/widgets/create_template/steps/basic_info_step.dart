import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

class BasicInfoStep extends StatelessWidget {
  final TextEditingController templateNameController;
  final bool includeWhatsApp;
  final bool includeSMS;
  final Function(bool) onWhatsAppChanged;
  final Function(bool) onSmsChanged;
  final bool showChannelError;

  const BasicInfoStep({
    super.key,
    required this.templateNameController,
    required this.includeWhatsApp,
    required this.includeSMS,
    required this.onWhatsAppChanged,
    required this.onSmsChanged,
    required this.showChannelError,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        TextFormField(
          controller: templateNameController,
          decoration: const InputDecoration(labelText: 'Template Name'),
          validator: (val) => val == null || val.trim().isEmpty
              ? 'Template name is required'
              : null,
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        CheckboxListTile(
          title: const Text('Send via WhatsApp'),
          value: includeWhatsApp,
          onChanged: (val) => onWhatsAppChanged(val ?? false),
        ),
        CheckboxListTile(
          title: const Text('Send via SMS'),
          value: includeSMS,
          onChanged: (val) => onSmsChanged(val ?? false),
        ),
        if (showChannelError)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Please select at least one channel (WhatsApp or SMS)',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
