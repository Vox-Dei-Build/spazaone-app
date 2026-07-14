import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/widgets/message_preview_card.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/promote/widgets/promotions/recepients.dart';
import 'package:pasella/utils/currency_util.dart';

String resolvePromotionPreviewContent({
  required String? templateContent,
  required String shopName,
  LinkedProductRef? product,
}) {
  final productPrice = product?.sellingPrice == null
      ? 'a price available in WhatsApp'
      : CurrencyUtil.format(product!.sellingPrice!);
  return (templateContent ?? 'No preview available')
      .replaceAll('{{customerName}}', '[Customer Name]')
      .replaceAll('{{shopName}}', shopName)
      .replaceAll('{{productName}}', product?.name.trim() ?? 'this product')
      .replaceAll('{{productPrice}}', productPrice);
}

class ReviewAndPricingStep extends StatelessWidget {
  final String? templateContent;
  final String? smsContent;
  final String? mediaUrl;
  final String shopName;
  final bool sendWhatsApp;
  final bool sendSMS;
  final double totalCost;
  final Map<String, dynamic> breakdown;
  final LinkedProductRef? linkedProduct;

  /// Optional list of all customers and the set of IDs selected for this promotion.
  final List<Map<String, dynamic>>? customers;
  final Set<String>? selectedCustomerIds;

  const ReviewAndPricingStep({
    Key? key,
    required this.templateContent,
    this.smsContent,
    required this.mediaUrl,
    required this.shopName,
    required this.sendWhatsApp,
    required this.sendSMS,
    required this.totalCost,
    required this.breakdown,
    this.linkedProduct,
    this.customers,
    this.selectedCustomerIds,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final resolved = resolvePromotionPreviewContent(
      templateContent: templateContent,
      shopName: shopName,
      product: linkedProduct,
    );

    // ─── Null‑safe unpacking ──────────────────────────
    final int whatsappCount = (breakdown['whatsappCount'] as int?) ?? 0;
    final double whatsappUnit =
        (breakdown['whatsappUnit'] as num?)?.toDouble() ?? 0.0;

    final int smsCount = (breakdown['smsCount'] as int?) ?? 0;
    final double smsUnit = (breakdown['smsUnit'] as num?)?.toDouble() ?? 0.0;
    final int smsSegments = (breakdown['smsSegments'] as int?) ?? 1;
    final int unknownCount = (breakdown['unknownCount'] as int?) ?? 0;
    final double unknownUnit =
        (breakdown['unknownUnit'] as num?)?.toDouble() ?? 0.0;
    // ─────────────────────────────────────────────────

    return SingleChildScrollView(
      padding: LayoutConstants.padding10Horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (linkedProduct != null) ...[
            _AttachedProductReview(product: linkedProduct!),
            SizedBox(height: SizeConfig.heightMultiplier * 1.5),
          ],
          // WhatsApp block
          if (sendWhatsApp) ...[
            Text(
              "WhatsApp Preview",
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.8,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              "$whatsappCount WhatsApp recipient${whatsappCount == 1 ? '' : 's'} "
              "@ ${CurrencyUtil.format(whatsappUnit)} = "
              "${CurrencyUtil.format(whatsappCount * whatsappUnit)}",
              textAlign: TextAlign.center,
            ),
            MessagePreviewCard(content: resolved, mediaUrl: mediaUrl),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
          ],

          // SMS block
          if (sendSMS) ...[
            Text(
              "SMS Preview",
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.8,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              "$smsCount SMS recipient${smsCount == 1 ? '' : 's'} × "
              "$smsSegments segment${smsSegments == 1 ? '' : 's'} "
              "@ ${CurrencyUtil.format(smsUnit)} = "
              "${CurrencyUtil.format(smsCount * smsUnit * smsSegments)}",
              textAlign: TextAlign.center,
            ),
            if (smsSegments > 1)
              Padding(
                padding: EdgeInsets.only(
                  top: SizeConfig.heightMultiplier * 0.5,
                ),
                child: Text(
                  "This SMS is long enough to be sent as $smsSegments segments, "
                  "so each recipient is charged for $smsSegments messages.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.4,
                    color: Colors.grey.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            MessagePreviewCard(content: smsContent ?? resolved),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
          ],

          if (unknownCount > 0)
            Text(
              '$unknownCount recipient${unknownCount == 1 ? '' : 's'} will be '
              'checked at send time @ up to '
              '${CurrencyUtil.format(unknownUnit)} each.',
              textAlign: TextAlign.center,
            ),

          // Channel-fallback explainer (only when both channels are on)
          if (sendWhatsApp && sendSMS)
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: SizeConfig.heightMultiplier * 0.5,
              ),
              child: Text(
                "Each recipient receives WhatsApp if available, otherwise SMS.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.4,
                  color: Colors.grey.shade700,
                ),
              ),
            ),

          // Recipients list (shrink‑wrapped inside)
          if (customers != null && selectedCustomerIds != null) ...[
            SelectedCustomersRecipients(
              customers: customers!,
              selectedCustomerIds: selectedCustomerIds!,
              onCustomerTap: (customer) {
                /* … */
              },
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
          ],

          const Divider(color: Colors.grey),

          // Total
          Text(
            "Total: ${CurrencyUtil.format(totalCost)}",
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 2,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AttachedProductReview extends StatelessWidget {
  final LinkedProductRef product;

  const _AttachedProductReview({required this.product});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availability = product.whatsappListed == true
        ? 'The Order on WhatsApp button will open this shop.'
        : product.whatsappListed == false
            ? 'This product is not listed for WhatsApp orders yet.'
            : 'Attached to this campaign for tracking.';
    final availabilityColor = product.whatsappListed == true
        ? Colors.green.shade700
        : product.whatsappListed == false
            ? Colors.orange.shade800
            : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attached product',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  product.name.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (product.sellingPrice != null)
                  Text(CurrencyUtil.format(product.sellingPrice!)),
                const SizedBox(height: 2),
                Text(
                  availability,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: availabilityColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
