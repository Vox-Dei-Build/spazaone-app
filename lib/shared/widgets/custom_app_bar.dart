import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomAppBar({
    super.key,
    required this.title,
    this.trailing,
    this.onBack = true,
    this.leading,
    this.onBackPressed,
  });

  final String title;
  final Widget? trailing;
  final bool onBack;
  final Widget? leading;
  final VoidCallback? onBackPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      automaticallyImplyLeading: false,
      leadingWidth: 56,
      leading: onBack
          ? IconButton(
              onPressed: () {
                FocusScope.of(context).unfocus();
                if (onBackPressed != null) {
                  onBackPressed!();
                } else {
                  Navigator.maybePop(context);
                }
              },
              icon: const Icon(SpazaIcons.back, size: 22),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            )
          : leading,
      title: Text(
        title,
        style: theme.appBarTheme.titleTextStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      centerTitle: false,
      actions: [if (trailing != null) trailing!, const SizedBox(width: 8)],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
