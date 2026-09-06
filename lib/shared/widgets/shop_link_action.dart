import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
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
    this.compact = false,
  });

  final VoidCallback onPressed;
  final String? storeName;
  final bool fillWidth;
  final bool compact;

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
      'Shop',
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
            foregroundColor: SpazaColors.heading,
            backgroundColor: SpazaColors.surface,
            minimumSize: Size(compact ? 96 : 104, 48),
            fixedSize: !fillWidth ? const Size(104, 48) : null,
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
            tapTargetSize: MaterialTapTargetSize.padded,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SpazaRadius.control),
            ),
            textStyle: const TextStyle(
              fontFamily: 'SpazaSans',
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: Row(
            mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              SizedBox(width: compact ? 6 : 8),
              const Flexible(child: label),
            ],
          ),
        ),
      ),
    );
  }
}
