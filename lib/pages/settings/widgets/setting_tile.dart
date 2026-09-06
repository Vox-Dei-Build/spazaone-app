import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/utils/text_sanitizer.dart';

/// Shared approachable row for settings and shop destinations. Text follows the
/// app theme; its height can grow with accessibility text instead of clipping.
class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    this.icon,
    required this.title,
    this.subTitle,
    this.onTap,
    this.trailing,
    this.hideDivider = false,
    this.removeLPadding,
    this.isDestructive = false,
  });

  final IconData? icon;
  final dynamic title;
  final dynamic subTitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool? hideDivider;
  final bool? removeLPadding;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = isDestructive ? theme.colorScheme.error : kTertiaryColor;
    return Column(
      children: [
        ListTile(
          minTileHeight: 56,
          minVerticalPadding: 12,
          minLeadingWidth: 36,
          horizontalTitleGap: 12,
          onTap: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SpazaRadius.surface),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: removeLPadding == true ? 0 : 12,
          ),
          leading: icon == null
              ? null
              : Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDestructive
                        ? theme.colorScheme.errorContainer.withValues(alpha: .3)
                        : SpazaColors.subtle,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: foreground, size: 22),
                ),
          title: title is String
              ? Text(
                  (title as String).sanitized(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w500,
                  ),
                )
              : title,
          subtitle: subTitle is String
              ? Text(
                  (subTitle as String).sanitized(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kSecondaryAccent,
                  ),
                )
              : subTitle,
          trailing: trailing ??
              (onTap == null
                  ? null
                  : const Icon(
                      SpazaIcons.next,
                      size: 20,
                      color: kSecondaryAccent,
                    )),
        ),
        if (hideDivider != true)
          Divider(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .6),
            height: 1,
            thickness: 1,
            indent: icon == null ? 8 : 42,
            endIndent: 8,
          ),
      ],
    );
  }
}
