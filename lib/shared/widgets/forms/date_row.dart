import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/constants/layout_constants.dart';

/// Single row for picking a date inside transaction/sale forms.
///
/// Replaces the three separate date-row patterns audited in the legacy
/// add_credit / add_payment / add_sale screens (some of which round-tripped
/// through `DateFormat.parse` on every render and lost the time
/// component). This widget:
///
/// - takes a real `DateTime` value so callers don't have to format/parse
///   strings between picks;
/// - renders a calendar icon to make the affordance obvious;
/// - meets the 44pt minimum touch target;
/// - uses `intl` so the user sees a locale-appropriate date.
class DateRow extends StatelessWidget {
  const DateRow({
    super.key,
    required this.label,
    required this.value,
    required this.onPick,
    this.firstDate,
    this.lastDate,
    this.helpText,
  });

  /// Label shown to the left of the picker button (e.g. "Date of Credit").
  final String label;

  /// Currently selected date.
  final DateTime value;

  /// Called with the new date when the user picks one. Not called on
  /// cancel.
  final ValueChanged<DateTime> onPick;

  /// Earliest selectable date. Defaults to year 2000.
  final DateTime? firstDate;

  /// Latest selectable date. Defaults to today (back-dating only).
  final DateTime? lastDate;

  /// Optional help text shown above the date picker dialog.
  final String? helpText;

  @override
  Widget build(BuildContext context) {
    final formatted = DateFormat.yMMMd().format(value);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LayoutConstants.spaceSm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: LayoutConstants.minTouchTarget,
            ),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(formatted),
              style: OutlinedButton.styleFrom(
                foregroundColor: kTertiaryColor,
                side: const BorderSide(color: kSecondaryAccent),
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutConstants.spaceLg,
                  vertical: LayoutConstants.spaceSm,
                ),
              ),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: value,
                  firstDate: firstDate ?? DateTime(2000),
                  lastDate: lastDate ?? DateTime.now(),
                  helpText: helpText,
                );
                if (picked != null) {
                  // Preserve the original time-of-day so callers that
                  // store a full timestamp (e.g. Sales `dateAdded`) don't
                  // silently snap everything to midnight.
                  final merged = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    value.hour,
                    value.minute,
                  );
                  onPick(merged);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
