import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';

String? validateStockAmount(String? value) {
  final input = value?.trim() ?? '';
  if (input.isEmpty) return null;

  final parsed = double.tryParse(input);
  if (parsed == null || parsed < 0) {
    return 'Enter a valid stock amount or leave it empty';
  }
  return null;
}

/// Optional rand value spent buying stock for the recorded sale/day.
///
/// This is deliberately separate from product quantities and calculated
/// cost of goods sold. A merchant can record a wholesaler purchase even when
/// they do not itemise products in the sale.
class StockAmountField extends StatelessWidget {
  const StockAmountField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomTextField(
          label: 'Stock amount (optional)',
          hintText: 'Enter amount spent on stock',
          prefixIcon: Icons.inventory_2_outlined,
          controller: controller,
          textInputType: const TextInputType.numberWithOptions(decimal: true),
          validator: validateStockAmount,
          margin: EdgeInsets.zero,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LayoutConstants.spaceMd,
            0,
            LayoutConstants.spaceMd,
            LayoutConstants.spaceSm,
          ),
          child: Text(
            'Money spent buying stock today — not units on hand.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: kSecondaryAccent,
                ),
          ),
        ),
      ],
    );
  }
}
