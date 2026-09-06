import 'package:flutter/material.dart';

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
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hint ?? 'Search…',
        prefixIcon: const Icon(Icons.search_rounded),
      ),
    );
  }
}
