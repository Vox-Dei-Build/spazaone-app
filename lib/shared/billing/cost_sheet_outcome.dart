/// Outcome of a [CostConfirmationSheet] interaction.
///
/// The sheet is the merchant's last chance to consent to a wallet
/// deduction before the dispatcher fires a paid message. Historically
/// the sheet returned a single `bool` and "cancel" silently meant
/// "skip the message" — merchants had no way to tell whether their
/// transaction had been recorded, whether a message had been sent, or
/// whether the dialog had simply been dismissed by an OS interruption.
///
/// The tri-state outcome makes that intent explicit:
///
///  * [send]      — the merchant confirmed; the dispatcher should send.
///  * [skip]      — the merchant explicitly chose "Skip & record only";
///                  the action persists, no message goes out.
///  * [dismissed] — the sheet was dismissed without an explicit choice
///                  (back gesture, scrim tap, OS interruption). Treat
///                  the same as [skip] from a side-effect perspective,
///                  but the caller should surface a snackbar so the
///                  merchant knows the action still committed.
enum CostSheetOutcome {
  send,
  skip,
  dismissed,
}

extension CostSheetOutcomeX on CostSheetOutcome {
  /// True only when the merchant explicitly confirmed the deduction.
  bool get shouldSend => this == CostSheetOutcome.send;

  /// True when no message goes out (skip OR dismissed). Callers should
  /// emit a snackbar in this case so the persisted-but-no-message
  /// state is never invisible.
  bool get isSilent => this != CostSheetOutcome.send;
}
