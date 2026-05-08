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

  /// Final total in ZAR. Authoritative — must equal the sum of `lines`
  /// where `isPrimary == true` (alternative/fallback lines are
  /// informational only and don't contribute to the quoted total). Callers
  /// can pre-round to avoid float drift.
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

  /// A multi-channel single-message breakdown.
  ///
  /// The dispatch path tries WhatsApp first when the recipient is known
  /// to have it (or when we need to recheck), and falls back to SMS
  /// otherwise. Quoting only one channel is a money-correctness bug —
  /// users get charged the OTHER price when the channel they didn't see
  /// quoted ends up delivering. This factory produces a breakdown that:
  ///
  ///   * Always shows BOTH channel costs to the user.
  ///   * Marks the most likely channel as the primary line (counts toward
  ///     the quoted total).
  ///   * Marks the alternative as a non-primary fallback line, rendered
  ///     muted by the sheet with an explanatory hint.
  ///   * Adds a note explaining the priority rules so the user can read
  ///     the quote without surprise.
  ///
  /// The quoted `total` is the cost of the EXPECTED channel only — it's
  /// what the user will see deducted on the happy path. The wallet
  /// affordability check uses this same total. If the actual delivery
  /// falls back to the other channel the deduction matches the
  /// alternative line, which is shown right above the total so there's
  /// no surprise.
  factory CostBreakdown.singleMessageMultiChannel({
    required String title,
    String? subtitle,
    required double whatsappCost,
    required double smsCost,
    required MessageChannelExpectation expected,
    List<String> notes = const [],
  }) {
    final whatsappPrimary = expected == MessageChannelExpectation.whatsapp ||
        expected == MessageChannelExpectation.unknown;
    final smsPrimary = expected == MessageChannelExpectation.sms;

    final whatsappLine = CostLine(
      label: 'WhatsApp',
      detail: whatsappPrimary
          ? null
          : (expected == MessageChannelExpectation.sms
              ? 'Used only if SMS fails'
              : null),
      amount: whatsappCost,
      isPrimary: whatsappPrimary,
    );
    final smsLine = CostLine(
      label: 'SMS',
      detail: smsPrimary
          ? null
          : (expected == MessageChannelExpectation.whatsapp
              ? 'Used only if WhatsApp fails'
              : 'Fallback if WhatsApp delivery fails'),
      amount: smsCost,
      isPrimary: smsPrimary,
    );

    // Always order: primary first, then alternative.
    final lines = whatsappPrimary
        ? <CostLine>[whatsappLine, smsLine]
        : <CostLine>[smsLine, whatsappLine];

    final total = whatsappPrimary ? whatsappCost : smsCost;

    final fullNotes = <String>[
      ...notes,
      switch (expected) {
        MessageChannelExpectation.whatsapp =>
          'This number has WhatsApp, so we\'ll send via WhatsApp first.',
        MessageChannelExpectation.sms =>
          'This number doesn\'t have WhatsApp, so we\'ll send via SMS.',
        MessageChannelExpectation.unknown =>
          'We try WhatsApp first; if it fails, we send via SMS.',
      },
    ];

    return CostBreakdown(
      title: title,
      subtitle: subtitle,
      lines: lines,
      total: total,
      notes: fullNotes,
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

  /// Whether this line contributes to the quoted total.
  ///
  /// Most lines are primary (`true`). Multi-channel single-message
  /// quotes use `isPrimary == false` to display the *alternative*
  /// fallback channel cost so the user can see what they would be
  /// charged on the unhappy path, without that figure being added to
  /// the headline total. The sheet renders non-primary lines with a
  /// muted style.
  final bool isPrimary;

  const CostLine({
    required this.label,
    required this.amount,
    this.detail,
    this.isPrimary = true,
  });
}

/// What channel we expect a single-recipient message to be delivered
/// over, used to bias the cost-confirmation sheet to the most likely
/// price while still disclosing the fallback.
///
/// The dispatch logic in `MessagingNotificationService.sendFormattedMessage`
/// tries WhatsApp first when the recipient is a known WhatsApp user (or
/// when the cached check is stale) and falls back to SMS if WhatsApp
/// delivery fails. This enum lets callers pre-resolve their best guess
/// so the sheet quotes the right primary price.
enum MessageChannelExpectation {
  /// Recipient is a known WhatsApp user — quote WhatsApp as primary,
  /// SMS as fallback.
  whatsapp,

  /// Recipient is known NOT to have WhatsApp (or has previously failed
  /// WhatsApp delivery) — quote SMS as primary, WhatsApp as fallback
  /// (still shown because rechecks happen periodically).
  sms,

  /// We don't know yet (e.g. brand-new contact). The dispatcher tries
  /// WhatsApp first by default, so quote WhatsApp as primary with SMS
  /// as fallback and an explanatory note.
  unknown,
}
