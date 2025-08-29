import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

class OrderSearchField extends StatelessWidget {
  const OrderSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.7),
      decoration: InputDecoration(
        hintText: hint ?? 'Search…',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 3,
          vertical: SizeConfig.heightMultiplier * 1.6,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
