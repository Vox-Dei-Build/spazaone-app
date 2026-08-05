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
  });

  final VoidCallback onPressed;
  final String? storeName;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final resolvedStoreName = storeName?.trim() ?? '';
    final useStackedLayout = MediaQuery.textScalerOf(context).scale(13) >= 20;
    final semanticLabel = resolvedStoreName.isEmpty
        ? 'Open your WhatsApp ordering link'
        : 'Open $resolvedStoreName WhatsApp ordering link';
    final icon = FaIcon(
      FontAwesomeIcons.whatsapp,
      size: 18,
      color: primary,
    );
    final label = Text(
      useStackedLayout ? 'Shop\nlink' : 'Shop link',
      maxLines: useStackedLayout ? 2 : 1,
      softWrap: useStackedLayout,
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
            minimumSize: const Size(0, 48),
            padding: EdgeInsets.symmetric(
              horizontal: useStackedLayout ? 10 : 14,
              vertical: useStackedLayout ? 6 : 0,
            ),
            tapTargetSize: MaterialTapTargetSize.padded,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: useStackedLayout
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(height: 2),
                    label,
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
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
