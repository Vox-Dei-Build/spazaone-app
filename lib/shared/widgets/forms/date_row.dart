import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:intl/intl.dart';

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
/// - meets the 48px minimum touch target;
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

  Future<void> _pickDate(BuildContext context) async {
    final first = DateUtils.dateOnly(firstDate ?? DateTime(2000));
    final last = DateUtils.dateOnly(lastDate ?? DateTime.now());
    final selected = DateUtils.dateOnly(value);
    final initial = selected.isBefore(first)
        ? first
        : selected.isAfter(last)
            ? last
            : selected;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: helpText,
    );
    if (picked == null) return;
    // Selecting a calendar day must not modify the stored time or precision.
    final createDate = value.isUtc ? DateTime.utc : DateTime.new;
    onPick(createDate(
      picked.year,
      picked.month,
      picked.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final formatted = DateFormat.yMMMd().format(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelText = Text(label, style: theme.textTheme.labelMedium);
          final picker = Semantics(
            label: label,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(formatted, textAlign: TextAlign.center),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: colors.onSurface,
                side: BorderSide(color: colors.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SpazaRadius.control),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                textStyle: theme.textTheme.bodyMedium,
              ),
              onPressed: () => _pickDate(context),
            ),
          );
          if (constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(14) > 20) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(child: labelText),
                const SizedBox(height: 4),
                picker,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: ExcludeSemantics(child: labelText)),
              const SizedBox(width: 12),
              Flexible(child: picker),
            ],
          );
        },
      ),
    );
  }
}
