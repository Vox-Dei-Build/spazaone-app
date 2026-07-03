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
import 'package:pasella/config/size_config.dart';
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
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            SizeConfig.imageSizeMultiplier * 4,
            SizeConfig.heightMultiplier * 1,
            SizeConfig.imageSizeMultiplier * 4,
            SizeConfig.heightMultiplier * 1,
          ),
          child: Row(
            children: [
              Expanded(
                child: _ActionPill(
                  label: 'Transaction',
                  icon: Icons.arrow_downward_rounded,
                  color: const Color(0xFFC62828),
                  onTap: () => _open(
                    context,
                    (ctx) => AddCreditScreen(
                      customerName: customerName,
                      customerId: customerId,
                      mobileNumber: mobileNumber,
                    ),
                  ),
                ),
              ),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 3),
              Expanded(
                child: _ActionPill(
                  label: 'Payment',
                  icon: Icons.arrow_upward_rounded,
                  color: const Color(0xFF1B5E20),
                  onTap: () => _open(
                    context,
                    (ctx) => AddPaymentScreen(
                      customerName: customerName,
                      customerId: customerId,
                      mobileNumber: mobileNumber,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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

class _ActionPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionPill({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(SizeConfig.imageSizeMultiplier * 4);
    return Material(
      color: color,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          height: SizeConfig.heightMultiplier * 6,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: Colors.white,
                  size: SizeConfig.imageSizeMultiplier * 5),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: SizeConfig.textMultiplier * 2,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
