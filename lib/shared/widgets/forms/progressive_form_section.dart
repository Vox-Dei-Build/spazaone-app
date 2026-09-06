import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

/// Keeps optional form work out of the way until the merchant asks for it.
///
/// The section opens once and stays open. This keeps any validation message or
/// attachment state visible after the user has started working in it.
class ProgressiveFormSection extends StatefulWidget {
  const ProgressiveFormSection({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.icon,
    required this.child,
    this.initiallyExpanded = false,
    this.hasValue = false,
    this.badge,
  });

  final String title;
  final String actionLabel;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;
  final bool hasValue;
  final String? badge;

  @override
  State<ProgressiveFormSection> createState() => _ProgressiveFormSectionState();
}

class _ProgressiveFormSectionState extends State<ProgressiveFormSection> {
  late bool _expanded = widget.initiallyExpanded || widget.hasValue;

  @override
  void didUpdateWidget(covariant ProgressiveFormSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && widget.hasValue && !oldWidget.hasValue) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_expanded) {
      return Padding(
        padding: const EdgeInsets.only(bottom: SpazaSpace.sm),
        child: OutlinedButton.icon(
          key: ValueKey('open-${widget.title.toLowerCase()}'),
          onPressed: () => setState(() => _expanded = true),
          icon: Icon(widget.icon, size: 20),
          label: Row(
            children: [
              Expanded(child: Text(widget.actionLabel)),
              if (widget.badge case final badge?) ...[
                const SizedBox(width: SpazaSpace.sm),
                Text(
                  badge,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: SpazaColors.muted,
                  ),
                ),
              ],
              const SizedBox(width: SpazaSpace.xs),
              const Icon(Icons.add_rounded, size: 20),
            ],
          ),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            backgroundColor: SpazaColors.surface,
            foregroundColor: SpazaColors.heading,
            padding: const EdgeInsets.symmetric(
              horizontal: SpazaSpace.md,
              vertical: SpazaSpace.md,
            ),
          ),
        ),
      );
    }

    return Container(
      key: ValueKey('expanded-${widget.title.toLowerCase()}'),
      margin: const EdgeInsets.only(bottom: SpazaSpace.md),
      padding: const EdgeInsets.fromLTRB(
        SpazaSpace.md,
        SpazaSpace.md,
        SpazaSpace.md,
        SpazaSpace.xs,
      ),
      decoration: BoxDecoration(
        color: SpazaColors.surface,
        border: Border.all(color: SpazaColors.border),
        borderRadius: BorderRadius.circular(SpazaRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 20, color: SpazaColors.heading),
              const SizedBox(width: SpazaSpace.sm),
              Expanded(
                child: Text(widget.title, style: theme.textTheme.titleSmall),
              ),
              if (widget.badge case final badge?)
                Text(
                  badge,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: SpazaColors.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: SpazaSpace.md),
          widget.child,
        ],
      ),
    );
  }
}
