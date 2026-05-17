import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasella/constants/layout_constants.dart';

/// Modal bottom sheet that lets the merchant type an exact quantity for
/// a line item instead of tapping +/- repeatedly. Returns the parsed
/// quantity (>= 0) on save, or `null` if the sheet was dismissed.
///
/// Stock validation is intentionally NOT done here — callers feed the
/// returned value into [TransactionViewModel.updateProductQuantity],
/// which is the single source of truth for the stock check + snackbar
/// recovery flow (see `transactional_view_model.dart:194`). Doing the
/// gate in two places would risk drift.
///
/// Mobile-first: bottom sheet with autofocused number keyboard and
/// resizable insets so the keyboard never covers the input. Safari /
/// iOS keyboard sensitivity: N/A — Flutter manages the keyboard
/// directly via `TextInputType.number`, no platform-specific quirks
/// observed against the existing number fields in the form (see
/// `add_credit.dart:62`).
class QuantityInputSheet extends StatefulWidget {
  final String productName;
  final int currentQuantity;

  const QuantityInputSheet({
    super.key,
    required this.productName,
    required this.currentQuantity,
  });

  static Future<int?> show(
    BuildContext context, {
    required String productName,
    required int currentQuantity,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuantityInputSheet(
        productName: productName,
        currentQuantity: currentQuantity,
      ),
    );
  }

  @override
  State<QuantityInputSheet> createState() => _QuantityInputSheetState();
}

class _QuantityInputSheetState extends State<QuantityInputSheet> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentQuantity.toString(),
    );
    // Select-all so the typical "tap and overwrite" flow doesn't need a
    // manual clear.
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) return;
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: LayoutConstants.spaceMd,
        right: LayoutConstants.spaceMd,
        top: LayoutConstants.spaceMd,
        bottom: LayoutConstants.spaceMd + bottomInset,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Quantity — ${widget.productName}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: LayoutConstants.spaceMd),
            TextFormField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a quantity';
                }
                final parsed = int.tryParse(value.trim());
                if (parsed == null) return 'Enter a whole number';
                if (parsed < 0) return 'Quantity cannot be negative';
                return null;
              },
            ),
            const SizedBox(height: LayoutConstants.spaceMd),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: LayoutConstants.spaceMd),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
