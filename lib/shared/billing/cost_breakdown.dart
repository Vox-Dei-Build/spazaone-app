/// A unified, presentation-friendly cost breakdown for any wallet-deducting
/// action.
///
/// Both single-message flows (e.g. add payment, add contact, send reminder)
/// and bulk-promotion flows produce the same shape so a single confirmation
/// surface (`CostConfirmationSheet`) and affordability footer
/// (`WalletAffordabilityFooter`) can render them.
///
/// Always work in ZAR; UI formats with `R` prefix.
class CostBreakdown {
  /// Human-readable title for the action being confirmed.
  /// e.g. "Send payment confirmation", "Run promotion".
  final String title;

  /// Optional subtitle / context. e.g. "12 customers, 1 SMS each".
  final String? subtitle;

  /// Itemised line items. Order is preserved.
  final List<CostLine> lines;

  /// Final total in ZAR. Authoritative — must equal `lines.sum(amount)` but
  /// callers can pre-round to avoid float drift.
  final double total;

  /// Optional explainer notes shown under the total
  /// (e.g. "Long messages count as 2 SMS segments").
  final List<String> notes;

  const CostBreakdown({
    required this.title,
    required this.total,
    this.subtitle,
    this.lines = const [],
    this.notes = const [],
  });

  /// Convenience: a single-line breakdown for a one-off message.
  factory CostBreakdown.singleMessage({
    required String title,
    String? subtitle,
    required String channelLabel,
    required double cost,
    List<String> notes = const [],
  }) {
    return CostBreakdown(
      title: title,
      subtitle: subtitle,
      lines: [CostLine(label: channelLabel, amount: cost)],
      total: cost,
      notes: notes,
    );
  }

  /// Build a breakdown from the legacy promotions map shape returned by
  /// `PromotionsViewModel.calculatePriceWithBreakdown`.
  factory CostBreakdown.fromPromotionMap({
    required String title,
    String? subtitle,
    required Map<String, dynamic> map,
    List<String> notes = const [],
  }) {
    final whatsappCount = (map['whatsappCount'] ?? 0) as int;
    final smsCount = (map['smsCount'] ?? 0) as int;
    final whatsappUnit = ((map['whatsappUnit'] ?? 0) as num).toDouble();
    final smsUnit = ((map['smsUnit'] ?? 0) as num).toDouble();
    final smsSegments = (map['smsSegments'] ?? 1) as int;
    final total = ((map['total'] ?? 0) as num).toDouble();

    final lines = <CostLine>[];
    if (whatsappCount > 0) {
      lines.add(
        CostLine(
          label: 'WhatsApp',
          detail:
              '$whatsappCount recipient${whatsappCount == 1 ? '' : 's'} × R${whatsappUnit.toStringAsFixed(2)}',
          amount: whatsappCount * whatsappUnit,
        ),
      );
    }
    if (smsCount > 0) {
      final segLabel = smsSegments == 1
          ? '1 segment'
          : '$smsSegments segments';
      lines.add(
        CostLine(
          label: 'SMS',
          detail:
              '$smsCount recipient${smsCount == 1 ? '' : 's'} × $segLabel × R${smsUnit.toStringAsFixed(2)}',
          amount: smsCount * smsSegments * smsUnit,
        ),
      );
    }

    return CostBreakdown(
      title: title,
      subtitle: subtitle,
      lines: lines,
      total: total,
      notes: notes,
    );
  }
}

/// One line item in a [CostBreakdown].
class CostLine {
  /// Short label, e.g. "SMS", "WhatsApp".
  final String label;

  /// Optional secondary detail explaining the line, e.g.
  /// "12 recipients × 2 segments × R0.30".
  final String? detail;

  /// Amount in ZAR.
  final double amount;

  const CostLine({
    required this.label,
    required this.amount,
    this.detail,
  });
}
