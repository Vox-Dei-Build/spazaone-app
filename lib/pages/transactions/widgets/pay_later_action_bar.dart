// Sticky bottom action bar for the Pay Later screen.
//
// Replaces the in-card `AddCreditPaymentButtons` row that used to be
// injected into the balance summary card's `children` slot. Lives in the
// `Scaffold.bottomNavigationBar` slot so it is always reachable, respects
// the device safe-area inset, and stays visually anchored while the user
// scrolls the ledger above it.
//
// Visual: two equally-weighted pill buttons separated by the page's
// horizontal padding, sitting on a thin top divider. Mirrors the WhatsApp
// "send / attach" anchored bar pattern that merchants are already used to.

import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/transactions/add_credit/add_credit.dart';
import 'package:pasella/pages/transactions/add_payment/add_payment.dart';
import 'package:pasella/utils/auth_util.dart';

class PayLaterActionBar extends StatelessWidget {
  final String customerName;
  final String customerId;
  final String? mobileNumber;

  const PayLaterActionBar({
    super.key,
    required this.customerName,
    required this.customerId,
    this.mobileNumber,
  });

  @override
  Widget build(BuildContext context) => CustomerAccountActions(
        onAddCredit: () => _open(
            context,
            (_) => AddCreditScreen(
                customerName: customerName,
                customerId: customerId,
                mobileNumber: mobileNumber)),
        onRecordPayment: () => _open(
            context,
            (_) => AddPaymentScreen(
                customerName: customerName,
                customerId: customerId,
                mobileNumber: mobileNumber)),
      );

  void _open(BuildContext context, WidgetBuilder builder) {
    // PAS-UX-14: gate at the screen edge so anonymous users see the
    // register prompt before the destination form is built.
    gateAndPush(
      context,
      push: () => Navigator.push(
        context,
        MaterialPageRoute(builder: builder),
      ),
    );
  }
}

/// The same account actions, with navigation supplied by the caller.
class CustomerAccountActions extends StatelessWidget {
  const CustomerAccountActions(
      {super.key, required this.onAddCredit, required this.onRecordPayment});
  final VoidCallback onAddCredit;
  final VoidCallback onRecordPayment;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: SpazaColors.border)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final add = _AccountAction(
                    label: 'Add to account',
                    icon: Icons.arrow_downward_rounded,
                    onPressed: onAddCredit,
                  );
                  final pay = _AccountAction(
                    label: 'Record payment',
                    icon: Icons.arrow_upward_rounded,
                    onPressed: onRecordPayment,
                  );
                  if (constraints.maxWidth < 340 ||
                      MediaQuery.textScalerOf(context).scale(14) > 19) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [add, const SizedBox(height: 8), pay],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: add),
                      const SizedBox(width: 12),
                      Expanded(child: pay),
                    ],
                  );
                },
              ),
            )),
      );
}

class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        label: Text(label, textAlign: TextAlign.center),
        style: FilledButton.styleFrom(
          backgroundColor: SpazaColors.subtle,
          foregroundColor: SpazaColors.heading,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}
