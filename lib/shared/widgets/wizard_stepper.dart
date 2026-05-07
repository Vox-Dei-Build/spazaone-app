import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

/// A compact, horizontal "1 — 2 — 3" progress indicator for multi-step wizards.
///
/// Shows numbered circles with labels underneath, joined by lines. The active
/// step is highlighted in the theme's primary colour, completed steps are
/// filled with a check icon, and upcoming steps are muted.
class WizardStepper extends StatelessWidget {
  /// Labels for each step, in order.
  final List<String> steps;

  /// Zero-based index of the currently active step.
  final int currentIndex;

  const WizardStepper({
    super.key,
    required this.steps,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final muted = theme.disabledColor;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 2,
        vertical: SizeConfig.heightMultiplier * 1.5,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            Expanded(
              child: _StepNode(
                index: i,
                label: steps[i],
                isActive: i == currentIndex,
                isComplete: i < currentIndex,
                primary: primary,
                muted: muted,
              ),
            ),
            if (i < steps.length - 1)
              Padding(
                padding: EdgeInsets.only(
                  // Align connector with the centre of the circle (24/2 = 12)
                  // accounting for label height below.
                  top: 11,
                ),
                child: SizedBox(
                  width: SizeConfig.imageSizeMultiplier * 4,
                  child: Container(
                    height: 2,
                    color: i < currentIndex ? primary : muted.withOpacity(0.3),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepNode extends StatelessWidget {
  final int index;
  final String label;
  final bool isActive;
  final bool isComplete;
  final Color primary;
  final Color muted;

  const _StepNode({
    required this.index,
    required this.label,
    required this.isActive,
    required this.isComplete,
    required this.primary,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color circleColor;
    final Color textColor;

    if (isComplete) {
      circleColor = primary;
      textColor = primary;
    } else if (isActive) {
      circleColor = primary;
      textColor = primary;
    } else {
      circleColor = muted.withOpacity(0.3);
      textColor = muted;
    }

    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isComplete || isActive ? circleColor : Colors.transparent,
            border: Border.all(color: circleColor, width: 2),
          ),
          child: isComplete
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: isActive ? Colors.white : muted,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: textColor,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
