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
        child: SizedBox(
          width: 48,
          height: 48,
          child: Material(
            color: primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FaIcon(
                    FontAwesomeIcons.whatsapp,
                    size: 18,
                    color: primary,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Shop',
                    maxLines: 1,
                    style: TextStyle(
                      color: primary,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
