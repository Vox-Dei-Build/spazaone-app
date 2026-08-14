import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// The shared entry point to the active store's WhatsApp storefront.
///
/// This action intentionally lives in the workspace row rather than the
/// logo row. That gives the label enough room to stay visible without
/// shrinking the Spaza One wordmark on narrow phones.
class ShopLinkAction extends StatelessWidget {
  const ShopLinkAction({
    super.key,
    required this.onPressed,
    this.storeName,
    this.fillWidth = false,
  });

  final VoidCallback onPressed;
  final String? storeName;
  final bool fillWidth;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final resolvedStoreName = storeName?.trim() ?? '';
    final semanticLabel = resolvedStoreName.isEmpty
        ? 'Open your WhatsApp ordering link'
        : 'Open $resolvedStoreName WhatsApp ordering link';
    final icon = FaIcon(
      FontAwesomeIcons.whatsapp,
      size: 18,
      color: primary,
    );
    const label = Text(
      'Shop link',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      textAlign: TextAlign.center,
    );

    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: semanticLabel,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: primary,
            backgroundColor: primary.withValues(alpha: 0.09),
            minimumSize: const Size(104, 48),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            tapTargetSize: MaterialTapTargetSize.padded,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Row(
            mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 8),
              label,
            ],
          ),
        ),
      ),
    );
  }
}
