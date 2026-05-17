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
class ProfileStatusIcon extends StatelessWidget {
  final bool isEnabled;
  final IconData enabledIcon;
  final IconData disabledIcon;
  final Color enabledColor;
  final Color disabledColor;
  final String? enabledTooltip;
  final String? disabledTooltip;

  const ProfileStatusIcon({
    Key? key,
    required this.isEnabled,
    required this.enabledIcon,
    required this.disabledIcon,
    this.enabledColor = Colors.green,
    this.disabledColor = Colors.red,
    this.enabledTooltip,
    this.disabledTooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      isEnabled ? enabledIcon : disabledIcon,
      color: isEnabled ? enabledColor : disabledColor,
      size: SizeConfig.imageSizeMultiplier * 3,
    );

    final message = isEnabled ? enabledTooltip : disabledTooltip;
    if (message == null || message.isEmpty) return icon;

    // Tap-to-explain. `triggerMode: tap` works on touch + desktop; the
    // tooltip also remains accessible to long-press and screen readers
    // because Tooltip wraps its child in a Semantics node.
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 3),
      preferBelow: false,
      child: icon,
    );
  }
}
