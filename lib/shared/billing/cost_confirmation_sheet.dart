import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/shared/billing/cost_breakdown.dart';
import 'package:pasella/shared/billing/wallet_balance_provider.dart';
import 'package:provider/provider.dart';

/// Modal bottom sheet that previews a wallet-deducting action's cost,
/// the user's current balance, and the resulting balance after deduction —
/// then asks for explicit confirmation.
///
/// Replaces the silent post-hoc "Insufficient Balance" alert dialog flow for
/// transactional sends (payments, credits, contacts, reminders).
///
/// Returns `true` if the user confirms, `false` if they cancel or top up.
class CostConfirmationSheet extends StatelessWidget {
  final CostBreakdown breakdown;
  final String confirmLabel;

  const CostConfirmationSheet({
    Key? key,
    required this.breakdown,
    this.confirmLabel = 'Confirm',
  }) : super(key: key);

  /// Show the sheet. Returns `true` only when the user explicitly confirms
  /// and has sufficient balance. Returns `false` for cancel, dismiss, or
  /// top-up navigation.
  static Future<bool> show(
    BuildContext context, {
    required CostBreakdown breakdown,
    String confirmLabel = 'Confirm',
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CostConfirmationSheet(
        breakdown: breakdown,
        confirmLabel: confirmLabel,
      ),
    );
    return result ?? false;
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

            // Itemised lines
            ...breakdown.lines.map((line) => Padding(
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
                              ),
                            ),
                            if (line.detail != null)
                              Text(
                                line.detail!,
                                style: TextStyle(
                                  fontSize: SizeConfig.textMultiplier * 1.4,
                                  color: Colors.black54,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        'R${line.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 1.7,
                        ),
                      ),
                    ],
                  ),
                )),

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
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (canAfford)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            vertical: SizeConfig.heightMultiplier * 1.2),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                  SizedBox(width: SizeConfig.imageSizeMultiplier * 3),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            vertical: SizeConfig.heightMultiplier * 1.2),
                        child: Text(confirmLabel),
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
                      Navigator.of(context).pop(false);
                      Provider.of<AppModel>(context, listen: false)
                          .goToBilling(context);
                    },
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 1),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
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
