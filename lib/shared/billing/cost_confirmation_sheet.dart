import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/shared/billing/cost_breakdown.dart';
import 'package:pasella/shared/billing/cost_sheet_outcome.dart';
import 'package:pasella/shared/billing/wallet_balance_provider.dart';
import 'package:pasella/shared/widgets/forms/confirm_dialog.dart';
import 'package:provider/provider.dart';
import 'package:pasella/utils/currency_util.dart';

/// Modal bottom sheet that previews a wallet-deducting action's cost,
/// the user's current balance, and the resulting balance after deduction —
/// then asks for explicit consent before any message is dispatched.
///
/// The sheet exposes explicit outcomes via [CostSheetOutcome]:
///
///  * `send`      — primary CTA, the dispatcher is allowed to charge.
///  * `skip`      — secondary CTA, the action persists but no message is
///                  sent. The default label is "Save without sending" so
///                  the UI states the actual outcome rather than what the
///                  merchant is _not_ doing — the previous "Don't send"
///                  read close enough to "Cancel" that release testers
///                  hesitated on it.
///  * `keepEditing` / `discard` — when dismissal confirmation is enabled,
///                  closing the sheet cannot silently persist the action.
///  * `dismissed` — sheet closed in a flow that does not request a discard
///                  confirmation. It must never imply permission to save.
///
/// The legacy [show] API is retained as a thin shim that maps `send` ->
/// `true` and everything else -> `false`, so older call sites that have
/// not yet migrated keep working unchanged. See
/// `docs/openclaw/pas-ux-03-implementation-note.md` for the rationale on
/// why the negative action must not read as "Cancel".
///
/// PAS-UX-12: Some flows have no underlying record to "save" if the
/// merchant decides not to send (for example, a standalone message with no
/// underlying sale, payment or credit record).
/// For those callers, set [showSkip] to `false` so the "Save without
/// sending" secondary action is omitted entirely. Dismissal is then
/// surfaced via an explicit close (X) icon in the header and the
/// standard back/scrim gesture, both of which return
/// [CostSheetOutcome.dismissed].
class CostConfirmationSheet extends StatelessWidget {
  final CostBreakdown breakdown;
  final String confirmLabel;
  final String skipLabel;
  final bool showSkip;

  const CostConfirmationSheet({
    Key? key,
    required this.breakdown,
    this.confirmLabel = 'Confirm',
    this.skipLabel = 'Save without sending',
    this.showSkip = true,
  }) : super(key: key);

  /// Tri-state variant. Prefer this for any caller that needs to
  /// distinguish "skip the message" from "cancel everything", or that
  /// wants to surface explicit feedback about what happened.
  static Future<CostSheetOutcome> showOutcome(
    BuildContext context, {
    required CostBreakdown breakdown,
    String confirmLabel = 'Send message',
    String skipLabel = 'Done without sending',
    bool showSkip = true,
    bool confirmDismissal = false,
    String dismissTitle = 'Discard this transaction?',
    String dismissMessage =
        'This transaction has not been saved. You can keep editing or discard it.',
  }) async {
    final result = await showModalBottomSheet<CostSheetOutcome>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CostConfirmationSheet(
        breakdown: breakdown,
        confirmLabel: confirmLabel,
        skipLabel: skipLabel,
        showSkip: showSkip,
      ),
    );
    if (result != null) return result;
    if (!confirmDismissal || !context.mounted) {
      return CostSheetOutcome.dismissed;
    }

    return confirmDiscardOrKeep(
      context,
      title: dismissTitle,
      message: dismissMessage,
    );
  }

  /// Resolves an attempted close for flows where the sheet sits between an
  /// editable form and its first persistence boundary.
  @visibleForTesting
  static Future<CostSheetOutcome> confirmDiscardOrKeep(
    BuildContext context, {
    String title = 'Discard this transaction?',
    String message =
        'This transaction has not been saved. You can keep editing or discard it.',
  }) async {
    final shouldDiscard = await ConfirmDialog.showDestructive(
      context,
      title: title,
      message: message,
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
    );
    return shouldDiscard
        ? CostSheetOutcome.discard
        : CostSheetOutcome.keepEditing;
  }

  /// Legacy bool variant. Returns `true` only when the user explicitly
  /// confirms and has sufficient balance. Returns `false` for skip,
  /// dismiss, or top-up navigation.
  ///
  /// Kept for backward compatibility — new code should prefer
  /// [showOutcome] so that "skip" can be told apart from "dismissed".
  static Future<bool> show(
    BuildContext context, {
    required CostBreakdown breakdown,
    String confirmLabel = 'Confirm',
    String skipLabel = 'Save without sending',
    bool showSkip = true,
  }) async {
    final outcome = await showOutcome(
      context,
      breakdown: breakdown,
      confirmLabel: confirmLabel,
      skipLabel: skipLabel,
      showSkip: showSkip,
    );
    return outcome.shouldSend;
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletBalanceProvider>();
    final loading = wallet.isLoading;
    final balance = wallet.virtualBalance;
    final cost = breakdown.total;
    final canAfford = !loading && balance >= cost;
    final after = balance - cost;

    return SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          SizeConfig.imageSizeMultiplier * 4,
          SizeConfig.heightMultiplier * 2,
          SizeConfig.imageSizeMultiplier * 4,
          SizeConfig.heightMultiplier * 3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            // Header row: title on the left, close (X) on the right.
            //
            // PAS-UX-12: The close icon is an explicit dismissal affordance
            // requested for flows where the secondary "Save without sending"
            // button is suppressed (e.g. standalone reminder send). Without
            // it the merchant would have no visible way out of the sheet
            // other than the back gesture / tapping the scrim, which is
            // not obvious on the bottom-sheet surface. Mapping it to
            // A null result lets [showOutcome] decide whether the caller
            // requires an explicit Discard / Keep editing choice.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        breakdown.title,
                        style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 2.4,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (breakdown.subtitle != null) ...[
                        SizedBox(height: SizeConfig.heightMultiplier * 0.5),
                        Text(
                          breakdown.subtitle!,
                          style: TextStyle(
                            fontSize: SizeConfig.textMultiplier * 1.6,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),

            // Itemised lines. Non-primary lines (e.g. the fallback
            // channel of a multi-channel single-message quote) are
            // rendered muted so the user can see what they'd be charged
            // if delivery falls back to the alternative channel without
            // it being mistaken for an additional charge.
            ...breakdown.lines.map((line) {
              final muted = !line.isPrimary;
              final labelColor = muted ? Colors.black54 : Colors.black87;
              final amountColor = muted ? Colors.black54 : Colors.black87;
              return Padding(
                padding: EdgeInsets.symmetric(
                  vertical: SizeConfig.heightMultiplier * 0.4,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.label,
                            style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 1.7,
                              color: labelColor,
                              fontStyle:
                                  muted ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                          if (line.detail != null)
                            Text(
                              line.detail!,
                              style: TextStyle(
                                fontSize: SizeConfig.textMultiplier * 1.4,
                                color: Colors.black54,
                                fontStyle:
                                    muted ? FontStyle.italic : FontStyle.normal,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      CurrencyUtil.format(line.amount),
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.7,
                        color: amountColor,
                        fontStyle: muted ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              );
            }),

            if (breakdown.lines.isNotEmpty) ...[const SizedBox(height: 18)],

            // Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  CurrencyUtil.format(cost),
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            // Notes
            if (breakdown.notes.isNotEmpty) ...[
              SizedBox(height: SizeConfig.heightMultiplier * 1),
              ...breakdown.notes.map(
                (n) => Padding(
                  padding: EdgeInsets.only(
                    top: SizeConfig.heightMultiplier * 0.3,
                  ),
                  child: Text(
                    n,
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.4,
                      color: Colors.black54,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ],

            SizedBox(height: SizeConfig.heightMultiplier * 2),

            // Balance summary
            Container(
              padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _balanceRow('Current balance', CurrencyUtil.format(balance)),
                  if (wallet.sharedCampaignCredits) ...[
                    SizedBox(height: SizeConfig.heightMultiplier * 0.5),
                    _balanceRow(
                      'Paid from',
                      'Shared SpazaOne balance',
                      valueBold: true,
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 0.5),
                    _balanceRow('Sending as', wallet.activeStoreName),
                  ],
                  SizedBox(height: SizeConfig.heightMultiplier * 0.5),
                  _balanceRow(
                    'Balance after',
                    canAfford
                        ? CurrencyUtil.format(after)
                        : 'Add money to send',
                    valueColor: canAfford
                        ? const Color(0xFF30345F)
                        : Colors.orange.shade800,
                    valueBold: true,
                  ),
                ],
              ),
            ),

            SizedBox(height: SizeConfig.heightMultiplier * 2.5),

            // Actions
            //
            // Three explicit outcomes (mapped to [CostSheetOutcome]):
            //   * Send                 -> CostSheetOutcome.send
            //   * Don't send           -> CostSheetOutcome.skip (only when
            //                             [showSkip] is true; PAS-UX-12)
            //   * Back / scrim / X     -> CostSheetOutcome.dismissed (null pop)
            //
            // The secondary action is explicit so merchants can skip the
            // outbound message without reading it as a destructive cancel
            // — except when there's nothing to save alongside the send,
            // in which case it's suppressed entirely and the close (X)
            // icon in the header is the only non-confirm exit.
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (canAfford)
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(CostSheetOutcome.send),
                      icon: const Icon(Icons.send_rounded, size: 19),
                      label: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: SizeConfig.heightMultiplier * 1.2,
                        ),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ),
                  if (showSkip) ...[
                    SizedBox(height: SizeConfig.heightMultiplier * 1),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(CostSheetOutcome.skip),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: SizeConfig.heightMultiplier * 1.2,
                          ),
                          child: Text(skipLabel),
                        ),
                      ),
                    ),
                  ],
                ],
              )
            else
              Column(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.account_balance_wallet),
                    label: const Text('Add money'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop(CostSheetOutcome.dismissed);
                      // Legacy `topUp` maps directly to Add money.
                      Provider.of<AppModel>(context, listen: false).goToBilling(
                        context,
                        initialTab: WalletInitialTab.topUp,
                      );
                    },
                  ),
                  if (showSkip) ...[
                    SizedBox(height: SizeConfig.heightMultiplier * 1),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(CostSheetOutcome.skip),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: SizeConfig.heightMultiplier * 1.2,
                          ),
                          child: Text(skipLabel),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _balanceRow(
    String label,
    String value, {
    Color? valueColor,
    bool valueBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 1.6,
            color: Colors.black87,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 1.6,
            color: valueColor ?? Colors.black87,
            fontWeight: valueBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
