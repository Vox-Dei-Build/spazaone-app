import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextField extends StatelessWidget {
  const CustomTextField({
    super.key,
    this.label,
    required this.hintText,
    required this.prefixIcon,
    this.textInputType,
    this.suffixOptions,
    this.controller,
    this.inputFormat,
    this.textCapitalization,
    this.obscureText,
    this.onChanged,
    this.maxLength,
    this.focusNode,
    this.margin,
    this.validator,
    this.autofillHints,
    this.textInputAction,
    this.onFieldSubmitted,
    this.readOnly = false,
  });

  final String? label;
  final String hintText;
  final IconData prefixIcon;
  final TextInputType? textInputType;
  final Widget? suffixOptions;
  final TextEditingController? controller;
  final List<TextInputFormatter>? inputFormat;
  final TextCapitalization? textCapitalization;
  final bool? obscureText;
  final Function(String)? onChanged;
  final int? maxLength;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry? margin;
  final String? Function(String?)? validator;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: margin ?? const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            ExcludeSemantics(
              child: Text(
                label!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Semantics(
            label: label,
            child: TextFormField(
              controller: controller,
              validator: validator,
              focusNode: focusNode,
              onChanged: onChanged,
              maxLength: maxLength,
              obscureText: obscureText ?? false,
              obscuringCharacter: '●',
              textCapitalization: textCapitalization ?? TextCapitalization.none,
              inputFormatters: inputFormat,
              keyboardType: textInputType,
              autofillHints: autofillHints,
              textInputAction: textInputAction,
              onFieldSubmitted: onFieldSubmitted,
              style: theme.textTheme.bodyMedium,
              readOnly: readOnly,
              decoration: InputDecoration(
                counterText: '',
                constraints: const BoxConstraints(minHeight: 52),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                hintText: hintText,
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                errorMaxLines: 6,
                prefixIcon:
                    Icon(prefixIcon, color: colors.onSurfaceVariant, size: 20),
                suffixIcon: suffixOptions,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
