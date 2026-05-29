import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/shared/billing/cost_breakdown.dart';
import 'package:pasella/shared/billing/cost_sheet_outcome.dart';
import 'package:pasella/shared/billing/wallet_balance_provider.dart';
import 'package:provider/provider.dart';

/// Modal bottom sheet that previews a wallet-deducting action's cost,
/// the user's current balance, and the resulting balance after deduction —
/// then asks for explicit consent before any message is dispatched.
///
/// The sheet exposes three outcomes via [CostSheetOutcome]:
///
///  * `send`      — primary CTA, the dispatcher is allowed to charge.
///  * `skip`      — secondary CTA, the action persists but no message is
///                  sent. The default label is "Save without sending" so
///                  the UI states the actual outcome rather than what the
///                  merchant is _not_ doing — the previous "Don't send"
///                  read close enough to "Cancel" that release testers
///                  hesitated on it.
///  * `dismissed` — sheet closed without an explicit choice (back
///                  gesture, scrim, OS interruption). Treated the same
///                  as `skip` for side effects; callers should still
///                  surface a snackbar so the merchant knows the
///                  underlying record was kept.
///
/// The legacy [show] API is retained as a thin shim that maps `send` ->
/// `true` and everything else -> `false`, so older call sites that have
/// not yet migrated keep working unchanged. See
/// `docs/openclaw/pas-ux-03-implementation-note.md` for the rationale on
/// why the negative action must not read as "Cancel".
///
/// PAS-UX-12: Some flows have no underlying record to "save" if the
/// merchant decides not to send (e.g. the standalone payment reminder
/// from the contact kebab — there's no sale, no payment, no credit
/// being recorded alongside the message; the reminder *is* the action).
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
    String confirmLabel = 'Send',
    String skipLabel = 'Save without sending',
    bool showSkip = true,
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
    return result ?? CostSheetOutcome.dismissed;
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
      child: Padding(
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
            // [CostSheetOutcome.dismissed] keeps it semantically distinct
            // from "skip" so callers that care can still tell the cases
            // apart.
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
                  onPressed: () => Navigator.of(context)
                      .pop(CostSheetOutcome.dismissed),
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
                    vertical: SizeConfig.heightMultiplier * 0.4),
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
                              fontStyle: muted
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                          if (line.detail != null)
                            Text(
                              line.detail!,
                              style: TextStyle(
                                fontSize: SizeConfig.textMultiplier * 1.4,
                                color: Colors.black54,
                                fontStyle: muted
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      'R${line.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.7,
                        color: amountColor,
                        fontStyle:
                            muted ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              );
            }),

            if (breakdown.lines.isNotEmpty) ...[
              const Divider(height: 24),
            ],

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
                  'R${cost.toStringAsFixed(2)}',
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
              ...breakdown.notes.map((n) => Padding(
                    padding: EdgeInsets.only(
                        top: SizeConfig.heightMultiplier * 0.3),
                    child: Text(
                      n,
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.4,
                        color: Colors.black54,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )),
            ],

            SizedBox(height: SizeConfig.heightMultiplier * 2),

            // Balance summary
            Container(
              padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3),
              decoration: BoxDecoration(
                color: canAfford
                    ? Colors.green.withValues(alpha: 0.08)
                    : Colors.orange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _balanceRow(
                      'Current balance', 'R${balance.toStringAsFixed(2)}'),
                  SizedBox(height: SizeConfig.heightMultiplier * 0.5),
                  _balanceRow(
                    'Balance after',
                    canAfford
                        ? 'R${after.toStringAsFixed(2)}'
                        : 'Top up to send',
                    valueColor: canAfford
                        ? Colors.green.shade800
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
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context)
                          .pop(CostSheetOutcome.send),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            vertical: SizeConfig.heightMultiplier * 1.2),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ),
                  if (showSkip) ...[
                    SizedBox(height: SizeConfig.heightMultiplier * 1),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context)
                            .pop(CostSheetOutcome.skip),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: SizeConfig.heightMultiplier * 1.2),
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
                    label: const Text('Top Up Wallet'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop(CostSheetOutcome.dismissed);
                      // PAS-UX-WTC: jump straight to the Top-Up tab —
                      // landing on Withdraw here is what made merchants
                      // think the "Top Up" CTA didn't work.
                      Provider.of<AppModel>(context, listen: false)
                          .goToBilling(context,
                              initialTab: WalletInitialTab.topUp);
                    },
                  ),
                  if (showSkip) ...[
                    SizedBox(height: SizeConfig.heightMultiplier * 1),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context)
                            .pop(CostSheetOutcome.skip),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: SizeConfig.heightMultiplier * 1.2),
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

  Widget _balanceRow(String label, String value,
      {Color? valueColor, bool valueBold = false}) {
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
