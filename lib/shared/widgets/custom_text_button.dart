import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.title,
    required this.onTap,
    this.color,
    this.margin,
    this.width,
    this.height,
    this.fontSize,
    this.icon,
    this.radius,
    this.iconSize,
    this.isDisabled = false,
  });

  final String title;
  final VoidCallback onTap;
  final Color? color;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final double? fontSize;
  final IconData? icon;
  final double? radius;
  final double? iconSize;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: true,
      enabled: !isDisabled,
      label: title,
      onTap: isDisabled ? null : onTap,
      excludeSemantics: true,
      child: Container(
        margin: margin ?? const EdgeInsets.symmetric(horizontal: 8),
        width: width ?? double.infinity,
        constraints: BoxConstraints(
            minHeight: (height ?? 52).clamp(48, double.infinity).toDouble()),
        child: FilledButton(
          onPressed: isDisabled ? null : onTap,
          style: FilledButton.styleFrom(
            backgroundColor: color ?? colors.primary,
            foregroundColor: colors.onPrimary,
            disabledBackgroundColor: colors.onSurface.withValues(alpha: .08),
            disabledForegroundColor: colors.onSurface.withValues(alpha: .38),
            minimumSize: const Size(48, 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(radius ?? SpazaRadius.control),
            ),
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: iconSize ?? 20),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(title, textAlign: TextAlign.center)),
            ],
          ),
        ),
      ),
    );
  }
}
