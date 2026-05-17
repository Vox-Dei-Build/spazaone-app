import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/meta_chip.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/status_pill.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/whatsapp_delivery_pill.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';
import 'package:pasella/utils/string_utils.dart';

class HeaderCard extends StatelessWidget {
  const HeaderCard({
    super.key,
    required this.customerName,
    required this.statusText,
    required this.statusColor,
    required this.totalText,
    required this.dateText,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.orderId,
    this.paymentStatusText,
    this.paymentStatusColor,
    this.collectionPill, // NEW
    this.whatsAppState, // PAS-AI-02
  });

  final String customerName;
  final String statusText;
  final Color statusColor;
  final String totalText;
  final String dateText;
  final String paymentMethod;
  final String paymentStatus;
  final String orderId;

  final String? paymentStatusText;
  final Color? paymentStatusColor;
  final PillMeta? collectionPill;
  final WhatsAppDeliveryState? whatsAppState;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final resolvedPayText = (paymentStatusText ?? paymentStatus).trim();
    final hasPaymentPill = resolvedPayText.isNotEmpty;
    final hasCollectionPill = collectionPill != null; // NEW

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    totalText,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: SizeConfig.textMultiplier * 2.6,
                    ),
                  ),
                ),
                FittedBox(
                  child: Row(
                    children: [
                      // NEW: collection pill
                      if (hasCollectionPill) ...[
                        SizedBox(width: SizeConfig.imageSizeMultiplier * 1.5),
                        StatusPill(
                          text: collectionPill!.text,
                          color: collectionPill!.color,
                        ),
                      ],

                      // payment pill (BNPL-aware)
                      if (hasPaymentPill) ...[
                        SizedBox(width: SizeConfig.imageSizeMultiplier * 1.5),
                        StatusPill(
                          text: resolvedPayText,
                          color: paymentStatusColor ??
                              Theme.of(context).colorScheme.outline,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: SizeConfig.heightMultiplier * 0.6),

            // --- Order meta: id + date ---
            Text(
              'Order #$orderId • $dateText',
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.5,
                color: Colors.grey.shade700,
              ),
            ),

            SizedBox(height: SizeConfig.heightMultiplier * 1.2),

            // --- Meta chips: customer, method, payment status ---
            Wrap(
              spacing: SizeConfig.imageSizeMultiplier * 2,
              runSpacing: SizeConfig.heightMultiplier * 0.8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MetaChip(
                  icon: Icons.person,
                  label: formatStringToCamelCase(customerName),
                ),
                MetaChip(
                  icon: Icons.account_balance_wallet_outlined,
                  label: paymentMethod,
                ),
                MetaChip(
                  icon: Icons.verified_outlined,
                  label: formatStringToCamelCase(
                    resolvedPayText.isEmpty ? '—' : resolvedPayText,
                  ),
                ),
                // PAS-AI-02: WhatsApp delivery / reply visibility. Wraps onto
                // its own line on narrow screens so mobile layouts stay clean.
                if (whatsAppState != null)
                  WhatsAppDeliveryPill(state: whatsAppState!, compact: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
