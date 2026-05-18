import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

/// A small status indicator overlaid on a profile picture.
///
/// PAS-UX-08: when [enabledTooltip] / [disabledTooltip] are supplied the
/// icon becomes tap-to-explain: a short tooltip surfaces what the colour
/// means (e.g. "Owing R450" vs "Paid up", or "Phone on file" vs
/// "No phone number — add one to send reminders"). This is the lightest
/// affordance that lets new merchants learn the icons in context without
/// adding an onboarding step.
///
/// PAS-AUTH-02: tooltips alone aren't enough — merchants were guessing
/// what the phone icon meant because the affordance only fires on tap.
/// [enabledLabel] / [disabledLabel], when supplied, render a tiny text
/// pill next to the icon so the meaning is visible at a glance. The
/// tooltip stays in place for the long form. Pass `null` to fall back to
/// the icon-only behaviour (e.g. for very small avatars where a label
/// would overflow).
class ProfileStatusIcon extends StatelessWidget {
  final bool isEnabled;
  final IconData enabledIcon;
  final IconData disabledIcon;
  final Color enabledColor;
  final Color disabledColor;
  final String? enabledTooltip;
  final String? disabledTooltip;
  final String? enabledLabel;
  final String? disabledLabel;

  const ProfileStatusIcon({
    Key? key,
    required this.isEnabled,
    required this.enabledIcon,
    required this.disabledIcon,
    this.enabledColor = Colors.green,
    this.disabledColor = Colors.red,
    this.enabledTooltip,
    this.disabledTooltip,
    this.enabledLabel,
    this.disabledLabel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = isEnabled ? enabledColor : disabledColor;
    final icon = Icon(
      isEnabled ? enabledIcon : disabledIcon,
      color: color,
      size: SizeConfig.imageSizeMultiplier * 3,
    );

    final label = isEnabled ? enabledLabel : disabledLabel;

    Widget visual = icon;
    if (label != null && label.isNotEmpty) {
      // PAS-AUTH-02: pill with the icon + a short word so the affordance
      // is explicit without needing a tap. Background is a tinted version
      // of the status colour so the icon and pill read as one unit.
      visual = Container(
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 1,
          vertical: SizeConfig.heightMultiplier * 0.25,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: color, width: 1),
          borderRadius: BorderRadius.circular(SizeConfig.imageSizeMultiplier * 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isEnabled ? enabledIcon : disabledIcon,
              color: color,
              size: SizeConfig.imageSizeMultiplier * 2.6,
            ),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 0.6),
            Text(
              label,
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.2,
                color: color,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ],
        ),
      );
    }

    final message = isEnabled ? enabledTooltip : disabledTooltip;
    if (message == null || message.isEmpty) return visual;

    // Tap-to-explain. `triggerMode: tap` works on touch + desktop; the
    // tooltip also remains accessible to long-press and screen readers
    // because Tooltip wraps its child in a Semantics node.
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 3),
      preferBelow: false,
      child: visual,
    );
  }
}
