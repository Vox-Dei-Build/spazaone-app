import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Compact, explicit entry point to the merchant's WhatsApp ordering link.
///
/// The Customers header is already dense, so this keeps the footprint close
/// to an icon button while retaining an always-visible label. A bare chain
/// icon was ambiguous because the wallet also uses that symbol for shared
/// campaign credits.
class ShopLinkAction extends StatelessWidget {
  const ShopLinkAction({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Semantics(
      button: true,
      label: 'Open your WhatsApp ordering link',
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: 'Open your WhatsApp ordering link',
        child: TextButton.icon(
          onPressed: onPressed,
          icon: const FaIcon(
            FontAwesomeIcons.whatsapp,
            size: 17,
          ),
          label: const Text('Shop link'),
          style: TextButton.styleFrom(
            foregroundColor: primary,
            backgroundColor: primary.withValues(alpha: 0.08),
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.padded,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}
