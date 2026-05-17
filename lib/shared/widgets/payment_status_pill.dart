import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';

/// Small labelled chip that names the customer's payment status in plain
/// language, e.g. "Owing" (red) or "Paid up" (green).
///
/// Background — PAS-UX-08 ("NPA status indicator trust recovery"):
/// the original design used a coloured dot overlaid on the avatar, which
/// merchants — especially new ones — did not understand. A tap-to-reveal
/// tooltip was tried but the affordance is still hidden: nothing on screen
/// tells the merchant the dot is interactive.
///
/// This pill replaces the dot at the surfaces where there is room for it
/// (customer list row, customer profile header). It reads itself, so no
/// learning step is required, and it lives next to the balance amount so
/// the label and the number reinforce each other.
class PaymentStatusPill extends StatelessWidget {
  /// Customer's current balance. Negative => owing. Null => unknown.
  final double? balance;

  /// When `true`, renders a more compact variant for tight rows.
  final bool dense;

  const PaymentStatusPill({
    Key? key,
    required this.balance,
    this.dense = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final _Status status = _resolveStatus(balance);

    final double fontSize = SizeConfig.textMultiplier * (dense ? 1.15 : 1.3);
    final EdgeInsets padding = dense
        ? EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 1.4,
            vertical: SizeConfig.heightMultiplier * 0.25,
          )
        : EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 1.8,
            vertical: SizeConfig.heightMultiplier * 0.4,
          );

    return Semantics(
      label: status.semanticsLabel,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: status.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: status.foreground.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              status.icon,
              size: fontSize + 2,
              color: status.foreground,
            ),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 0.6),
            Text(
              status.label,
              style: TextStyle(
                color: status.foreground,
                fontWeight: FontWeight.w600,
                fontSize: fontSize,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static _Status _resolveStatus(double? balance) {
    if (balance == null) {
      return const _Status(
        label: 'No balance',
        semanticsLabel: 'No balance recorded',
        foreground: Color(0xff6b7280),
        background: Color(0xffeef2f4),
        icon: Icons.remove_circle_outline,
      );
    }
    if (balance < 0) {
      return const _Status(
        label: 'Owing',
        semanticsLabel: 'This client owes you money',
        foreground: Color(0xffb91c1c),
        background: Color(0xfffef2f2),
        icon: Icons.report_gmailerrorred,
      );
    }
    if (balance > 0) {
      return const _Status(
        label: 'In credit',
        semanticsLabel: 'This client is in credit',
        foreground: kPrimaryColor,
        background: kHighLightColor,
        icon: Icons.savings_outlined,
      );
    }
    return const _Status(
      label: 'Paid up',
      semanticsLabel: 'This client is paid up',
      foreground: kPrimaryColor,
      background: kHighLightColor,
      icon: Icons.verified_outlined,
    );
  }
}

class _Status {
  final String label;
  final String semanticsLabel;
  final Color foreground;
  final Color background;
  final IconData icon;

  const _Status({
    required this.label,
    required this.semanticsLabel,
    required this.foreground,
    required this.background,
    required this.icon,
  });
}
