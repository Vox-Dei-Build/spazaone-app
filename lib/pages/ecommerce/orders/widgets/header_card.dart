import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
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
    final resolvedPayText = (paymentStatusText ?? paymentStatus).trim();
    final hasPaymentPill = resolvedPayText.isNotEmpty;
    final hasCollectionPill = collectionPill != null; // NEW

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  totalText,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // NEW: collection pill
                    if (hasCollectionPill) ...[
                      StatusPill(
                        text: collectionPill!.text,
                        color: collectionPill!.color,
                      ),
                    ],

                    // payment pill (BNPL-aware)
                    if (hasPaymentPill) ...[
                      StatusPill(
                        text: resolvedPayText,
                        color: paymentStatusColor ??
                            Theme.of(context).colorScheme.outline,
                      ),
                    ],
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // --- Order meta: id + date ---
            Text(
              'Order #$orderId • $dateText',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SpazaColors.muted,
                  ),
            ),

            const SizedBox(height: 16),

            // --- Meta chips: customer, method, payment status ---
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MetaChip(
                  icon: SpazaIcons.customers,
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
