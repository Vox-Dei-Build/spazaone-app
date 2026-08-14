/// Outcome of a [CostConfirmationSheet] interaction.
///
/// The sheet is the merchant's last chance to consent to a wallet
/// deduction before the dispatcher fires a paid message. Historically
/// the sheet returned a single `bool` and "cancel" silently meant
/// "skip the message" — merchants had no way to tell whether their
/// transaction had been recorded, whether a message had been sent, or
/// whether the dialog had simply been dismissed by an OS interruption.
///
/// The outcome makes that intent explicit:
///
///  * [send]      — the merchant confirmed; the dispatcher should send.
///  * [skip]      — the merchant explicitly chose "Skip & record only";
///                  the action persists, no message goes out.
///  * [keepEditing] — the merchant closed the sheet and chose to return to
///                    the form. Nothing is persisted.
///  * [discard]   — the merchant explicitly discarded the pending action.
///                  Nothing is persisted and the form may be closed.
///  * [dismissed] — the sheet was dismissed without an explicit choice
///                  in a flow that does not request a discard confirmation.
///                  Nothing should be persisted from this outcome.
enum CostSheetOutcome {
  send,
  skip,
  keepEditing,
  discard,
  dismissed,
}

extension CostSheetOutcomeX on CostSheetOutcome {
  /// True only when the merchant explicitly confirmed the deduction.
  bool get shouldSend => this == CostSheetOutcome.send;

  /// Financial or inventory state may be committed only after one of the
  /// sheet's two explicit save actions.
  bool get shouldCommit =>
      this == CostSheetOutcome.send || this == CostSheetOutcome.skip;

  bool get shouldDiscard => this == CostSheetOutcome.discard;

  /// True when no message goes out. Callers that persist an associated
  /// record should first require [shouldCommit]; a dismissed sheet must not
  /// be treated as implicit consent to save.
  bool get isSilent => this != CostSheetOutcome.send;
}
