import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

class BasicInfoStep extends StatelessWidget {
  final TextEditingController templateNameController;
  final bool showChannelError;

  const BasicInfoStep({
    super.key,
    required this.templateNameController,
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
      ],
    );
  }
}
