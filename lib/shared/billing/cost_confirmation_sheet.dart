import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
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
///  * `skip`      — secondary CTA "Skip & record only", the action
///                  persists but no message is sent. Removes the silent
///                  "cancel == skip" trap from the previous bool API.
///  * `dismissed` — sheet closed without an explicit choice (back
///                  gesture, scrim, OS interruption). Treated the same
///                  as `skip` for side effects; callers should still
///                  surface a snackbar so the merchant knows the
///                  underlying record was kept.
///
/// The legacy [show] API is retained as a thin shim that maps `send` ->
/// `true` and everything else -> `false`, so older call sites that have
/// not yet migrated keep working unchanged.
class CostConfirmationSheet extends StatelessWidget {
  final CostBreakdown breakdown;
  final String confirmLabel;
  final String skipLabel;

  const CostConfirmationSheet({
    Key? key,
    required this.breakdown,
    this.confirmLabel = 'Confirm',
    this.skipLabel = 'Skip & record only',
  }) : super(key: key);

  /// Tri-state variant. Prefer this for any caller that needs to
  /// distinguish "skip the message" from "cancel everything", or that
  /// wants to surface explicit feedback about what happened.
  static Future<CostSheetOutcome> showOutcome(
    BuildContext context, {
    required CostBreakdown breakdown,
    String confirmLabel = 'Send',
    String skipLabel = 'Skip & record only',
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
  }) async {
    final outcome = await showOutcome(
      context,
      breakdown: breakdown,
      confirmLabel: confirmLabel,
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
            SizedBox(height: SizeConfig.heightMultiplier * 2),
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
                    ? Colors.green.withOpacity(0.08)
                    : Colors.orange.withOpacity(0.10),
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
                        : 'Insufficient',
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
            //   * Skip & record only   -> CostSheetOutcome.skip
            //   * Back / scrim dismiss -> CostSheetOutcome.dismissed (null pop)
            //
            // The Skip button is the antidote to the previous silent
            // "cancel == skip" trap: merchants now choose, in one tap,
            // whether to spend the wallet or persist without sending.
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
                      Provider.of<AppModel>(context, listen: false)
                          .goToBilling(context);
                    },
                  ),
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
