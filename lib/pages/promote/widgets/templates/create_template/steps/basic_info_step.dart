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
            helperText:
                'Lowercase, numbers & underscores only. We’ll tidy this next step.',
            floatingLabelBehavior: FloatingLabelBehavior.never,
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Template name is required';
            }
            // Allow any characters here; we sanitize on next step and on save.
            return null;
          },
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
      ],
    );
  }
}
