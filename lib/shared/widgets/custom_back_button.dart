import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

class CustomBackButton extends StatelessWidget {
  const CustomBackButton({
    super.key,
    required this.title,
    this.trailing,
    this.onBack = true,
  });

  final String title;
  final Widget? trailing;
  final bool? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Row(
        children: [
          if (onBack == true)
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.maybePop(context);
              },
              icon: const Icon(SpazaIcons.back, size: 22),
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
