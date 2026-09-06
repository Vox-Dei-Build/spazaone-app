// Subtle centered date divider for the chat-style ledger.
//
// Replaces the previous full-width dark-grey pill that re-stated the time
// of the last transaction in the group (misleading — the divider should
// describe the day, not a tx). Mirrors WhatsApp / Signal: a small centered
// chip with pale background, dark text, and human labels ("Today",
// "Yesterday", or a localised short date).

import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:intl/intl.dart';

class TransactionDate extends StatelessWidget {
  final String date;

  const TransactionDate(this.date, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 12,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: SpazaColors.subtle,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _humanize(date),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: SpazaColors.muted,
              fontSize: 13,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  /// Human-friendly day label. Falls back to the raw input only if we
  /// truly cannot parse it — the grouping key upstream is already an
  /// ISO-ish date string, so this is just defensive.
  String _humanize(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(parsed.year, parsed.month, parsed.day);
    final delta = today.difference(that).inDays;
    if (delta == 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    if (delta > 1 && delta < 7) return DateFormat('EEEE').format(parsed);
    if (parsed.year == now.year) return DateFormat('EEE d MMM').format(parsed);
    return DateFormat('d MMM y').format(parsed);
  }
}
