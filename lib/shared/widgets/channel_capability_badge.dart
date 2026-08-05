import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';

/// PAS-WA-V1: compact channel-capability chip rendered on the customer
/// tile in the ledger. Communicates "what will happen if I tap Send
/// Reminder?" honestly:
///
///   * [hasWhatsApp] == true  → green WhatsApp glyph + "WhatsApp"
///   * [hasWhatsApp] == false → blue SMS glyph + "SMS"
///   * [hasWhatsApp] == null  → grey phone glyph + "Phone"  (we don't
///                              know yet; do not fake certainty)
///   * [hasNumber] == false   → red phone-disabled glyph + "No phone"
///
/// Design constraints kept in mind for mobile:
///   * The pill is ~ icon + 1 short word. No paragraphs in the tile.
///   * Tooltip is the long-form explanation, surfaced on tap (matches
///     [ProfileStatusIcon]).
///   * Colours intentionally reuse [WaBrandColour.tealGreenLighter]
///     (WhatsApp), `Colors.blueGrey` (SMS), and grey shades so the
///     row keeps a calm, scan-friendly density.
class ChannelCapabilityBadge extends StatelessWidget {
  final bool hasNumber;
  final bool? hasWhatsApp;
  final double? iconSize;

  const ChannelCapabilityBadge({
    Key? key,
    required this.hasNumber,
    required this.hasWhatsApp,
    this.iconSize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final double size = iconSize ?? SizeConfig.imageSizeMultiplier * 2.6;

    final IconData icon;
    final Color color;
    final String label;
    final String tooltip;
    final bool isFontAwesome;

    if (!hasNumber) {
      icon = Icons.phone_disabled;
      color = Colors.red.shade400;
      label = 'No phone';
      tooltip = 'No phone number on file — add one to send reminders.';
      isFontAwesome = false;
    } else if (hasWhatsApp == true) {
      icon = FontAwesomeIcons.whatsapp;
      color = WaBrandColour.tealGreenLighter;
      label = 'WhatsApp';
      tooltip = 'Reachable on WhatsApp — reminders will use WhatsApp.';
      isFontAwesome = true;
    } else if (hasWhatsApp == false) {
      icon = Icons.sms_outlined;
      color = Colors.blueGrey.shade600;
      label = 'SMS';
      tooltip = 'Not on WhatsApp — reminders will be sent via SMS.';
      isFontAwesome = false;
    } else {
      icon = Icons.phone_outlined;
      color = Colors.grey.shade600;
      label = 'Phone';
      tooltip = 'WhatsApp status not yet checked. Spaza One tries WhatsApp '
          'first and falls back to SMS automatically.';
      isFontAwesome = false;
    }

    final pill = Container(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 1.2,
        vertical: SizeConfig.heightMultiplier * 0.2,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        border: Border.all(color: color.withOpacity(0.45), width: 0.8),
        borderRadius: BorderRadius.circular(SizeConfig.imageSizeMultiplier * 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          isFontAwesome
              ? FaIcon(icon, color: color, size: size)
              : Icon(icon, color: color, size: size),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 0.6),
          Text(
            label,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.1,
              color: color,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 3),
      preferBelow: false,
      child: pill,
    );
  }
}
