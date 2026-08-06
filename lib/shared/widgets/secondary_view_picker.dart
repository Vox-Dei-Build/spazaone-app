import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';

/// One option in a [SecondaryViewPicker].
///
/// Secondary views are deliberately presented as a menu instead of another
/// row of tabs. This keeps the app's primary tabs visually dominant while the
/// current sub-view remains visible and easy to change.
class SecondaryViewOption<T> {
  const SecondaryViewOption({
    required this.value,
    required this.label,
    required this.icon,
  });

  final T value;
  final String label;
  final IconData icon;
}

/// A quiet, accessible selector for changing a view inside a primary tab.
///
/// Only the current value is shown on the page. The alternatives live in a
/// popup menu, avoiding the visual weight and hierarchy confusion of a second
/// tab or segmented-button row.
class SecondaryViewPicker<T> extends StatelessWidget {
  const SecondaryViewPicker({
    super.key,
    required this.semanticLabel,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final String semanticLabel;
  final T value;
  final List<SecondaryViewOption<T>> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    assert(options.isNotEmpty);
    assert(options.any((option) => option.value == value));

    final selected = options.firstWhere((option) => option.value == value);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final showEyebrow = scaler.scale(12) < 20;

    return Align(
      alignment: Alignment.centerRight,
      child: PopupMenuButton<T>(
        initialValue: value,
        position: PopupMenuPosition.under,
        tooltip: 'Change $semanticLabel',
        onSelected: onSelected,
        itemBuilder: (context) {
          return options.map((option) {
            final isSelected = option.value == value;
            return PopupMenuItem<T>(
              value: option.value,
              child: Row(
                children: [
                  Icon(
                    option.icon,
                    size: 20,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: LayoutConstants.spaceMd),
                  Expanded(
                    child: Text(
                      option.label,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: LayoutConstants.spaceMd),
                    Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                  ],
                ],
              ),
            );
          }).toList(growable: false);
        },
        child: Semantics(
          container: true,
          button: true,
          label: '$semanticLabel: ${selected.label}',
          hint: 'Choose another view',
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: LayoutConstants.minTouchTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutConstants.spaceXs,
                  vertical: LayoutConstants.spaceXs,
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: LayoutConstants.spaceSm,
                  runSpacing: 0,
                  children: [
                    if (showEyebrow)
                      Text(
                        'VIEW',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected.icon,
                          size: 19,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: LayoutConstants.spaceSm),
                        Text(
                          selected.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: LayoutConstants.spaceXs),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
