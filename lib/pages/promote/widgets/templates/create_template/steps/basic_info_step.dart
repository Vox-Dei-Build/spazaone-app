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
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: const InputDecoration(
            labelText: 'Template Name',
            hintText: 'e.g. promo_sale_chicken',
            helperText: 'Lowercase, numbers & underscores only',
            floatingLabelBehavior: FloatingLabelBehavior.never,
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Template name is required';
            }
            final regex = RegExp(r'^[a-z0-9_]+$');
            if (!regex.hasMatch(val.trim())) {
              return 'Only lowercase letters, numbers, and underscores are allowed';
            }
            return null;
          },
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
      ],
    );
  }
}
