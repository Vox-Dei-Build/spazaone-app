import 'package:flutter/material.dart';
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

enum _ReviewPreviewChannel { whatsapp, sms }

class ReviewAndPricingStep extends StatefulWidget {
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
  State<ReviewAndPricingStep> createState() => _ReviewAndPricingStepState();
}

class _ReviewAndPricingStepState extends State<ReviewAndPricingStep> {
  late _ReviewPreviewChannel _previewChannel;

  @override
  void initState() {
    super.initState();
    _previewChannel = widget.sendWhatsApp
        ? _ReviewPreviewChannel.whatsapp
        : _ReviewPreviewChannel.sms;
  }

  @override
  void didUpdateWidget(covariant ReviewAndPricingStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_previewChannel == _ReviewPreviewChannel.whatsapp &&
        !widget.sendWhatsApp) {
      _previewChannel = _ReviewPreviewChannel.sms;
    } else if (_previewChannel == _ReviewPreviewChannel.sms &&
        !widget.sendSMS) {
      _previewChannel = _ReviewPreviewChannel.whatsapp;
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = resolvePromotionPreviewContent(
      templateContent: widget.templateContent,
      shopName: widget.shopName,
      product: widget.linkedProduct,
    );

    final int whatsappCount =
        (widget.breakdown['whatsappCount'] as num?)?.toInt() ?? 0;
    final double whatsappUnit =
        (widget.breakdown['whatsappUnit'] as num?)?.toDouble() ?? 0.0;

    final int smsCount = (widget.breakdown['smsCount'] as num?)?.toInt() ?? 0;
    final double smsUnit =
        (widget.breakdown['smsUnit'] as num?)?.toDouble() ?? 0.0;
    final int smsSegments =
        (widget.breakdown['smsSegments'] as num?)?.toInt() ?? 1;
    final int unknownCount =
        (widget.breakdown['unknownCount'] as num?)?.toInt() ?? 0;
    final double unknownUnit =
        (widget.breakdown['unknownUnit'] as num?)?.toDouble() ?? 0.0;
    final recipientCount = whatsappCount + smsCount + unknownCount;
    final channelLabel = widget.sendWhatsApp && widget.sendSMS
        ? 'WhatsApp with SMS fallback'
        : widget.sendWhatsApp
            ? 'WhatsApp'
            : 'SMS';
    final previewContent = _previewChannel == _ReviewPreviewChannel.whatsapp
        ? resolved
        : (widget.smsContent ?? resolved);

    return SingleChildScrollView(
      key: const Key('promotion-review-content'),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReviewSummaryCard(
            recipientCount: recipientCount,
            channelLabel: channelLabel,
            totalCost: widget.totalCost,
          ),
          const SizedBox(height: 12),
          if (widget.linkedProduct != null) ...[
            _AttachedProductReview(product: widget.linkedProduct!),
            const SizedBox(height: 12),
          ],
          _DeliveryBreakdownCard(
            sendWhatsApp: widget.sendWhatsApp,
            sendSMS: widget.sendSMS,
            whatsappCount: whatsappCount,
            whatsappUnit: whatsappUnit,
            smsCount: smsCount,
            smsUnit: smsUnit,
            smsSegments: smsSegments,
            unknownCount: unknownCount,
            unknownUnit: unknownUnit,
          ),
          const SizedBox(height: 16),
          _MessagePreviewSection(
            channel: _previewChannel,
            showWhatsApp: widget.sendWhatsApp,
            showSms: widget.sendSMS,
            onChannelChanged: (value) {
              setState(() => _previewChannel = value);
            },
            content: previewContent,
            mediaUrl: _previewChannel == _ReviewPreviewChannel.whatsapp
                ? widget.mediaUrl
                : null,
          ),
          if (widget.customers != null &&
              widget.selectedCustomerIds != null) ...[
            const SizedBox(height: 12),
            SelectedCustomersRecipients(
              customers: widget.customers!,
              selectedCustomerIds: widget.selectedCustomerIds!,
              onCustomerTap: (customer) {
                /* … */
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewSummaryCard extends StatelessWidget {
  const _ReviewSummaryCard({
    required this.recipientCount,
    required this.channelLabel,
    required this.totalCost,
  });

  final int recipientCount;
  final String channelLabel;
  final double totalCost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Container(
      key: const Key('promotion-review-summary'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.send_rounded, color: primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ready to send',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$recipientCount customer${recipientCount == 1 ? '' : 's'} · '
                  '$channelLabel',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                CurrencyUtil.format(totalCost),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                'estimated cost',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeliveryBreakdownCard extends StatelessWidget {
  const _DeliveryBreakdownCard({
    required this.sendWhatsApp,
    required this.sendSMS,
    required this.whatsappCount,
    required this.whatsappUnit,
    required this.smsCount,
    required this.smsUnit,
    required this.smsSegments,
    required this.unknownCount,
    required this.unknownUnit,
  });

  final bool sendWhatsApp;
  final bool sendSMS;
  final int whatsappCount;
  final double whatsappUnit;
  final int smsCount;
  final double smsUnit;
  final int smsSegments;
  final int unknownCount;
  final double unknownUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('promotion-delivery-breakdown'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Delivery',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          if (sendWhatsApp)
            _DeliveryRow(
              icon: Icons.chat_bubble_rounded,
              color: const Color(0xFF1B8F3A),
              title: 'WhatsApp',
              detail: '$whatsappCount × ${CurrencyUtil.format(whatsappUnit)}',
              amount: whatsappCount * whatsappUnit,
            ),
          if (sendSMS)
            _DeliveryRow(
              icon: Icons.sms_rounded,
              color: const Color(0xFF3746A0),
              title: 'SMS',
              detail: smsSegments == 1
                  ? '$smsCount × ${CurrencyUtil.format(smsUnit)}'
                  : '$smsCount × $smsSegments segments',
              amount: smsCount * smsUnit * smsSegments,
            ),
          if (unknownCount > 0)
            _DeliveryRow(
              icon: Icons.manage_search_rounded,
              color: Colors.orange.shade800,
              title: 'Checked when sent',
              detail:
                  '$unknownCount × up to ${CurrencyUtil.format(unknownUnit)}',
              amount: unknownCount * unknownUnit,
            ),
          if (sendWhatsApp && sendSMS) ...[
            const SizedBox(height: 4),
            Text(
              'WhatsApp first · SMS if unavailable',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.amount,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            CurrencyUtil.format(amount),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagePreviewSection extends StatelessWidget {
  const _MessagePreviewSection({
    required this.channel,
    required this.showWhatsApp,
    required this.showSms,
    required this.onChannelChanged,
    required this.content,
    required this.mediaUrl,
  });

  final _ReviewPreviewChannel channel;
  final bool showWhatsApp;
  final bool showSms;
  final ValueChanged<_ReviewPreviewChannel> onChannelChanged;
  final String content;
  final String? mediaUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Text(
      'Message preview',
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
    final channelControl = showWhatsApp && showSms
        ? SegmentedButton<_ReviewPreviewChannel>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: _ReviewPreviewChannel.whatsapp,
                label: Text('WhatsApp'),
              ),
              ButtonSegment(
                value: _ReviewPreviewChannel.sms,
                label: Text('SMS'),
              ),
            ],
            selected: {channel},
            onSelectionChanged: (selection) {
              onChannelChanged(selection.first);
            },
          )
        : Text(
            showWhatsApp ? 'WhatsApp' : 'SMS',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(14) > 17;
            if (showWhatsApp &&
                showSms &&
                (constraints.maxWidth < 360 || largeText)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  title,
                  const SizedBox(height: 8),
                  channelControl,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: title),
                channelControl,
              ],
            );
          },
        ),
        MessagePreviewCard(
          content: content,
          mediaUrl: mediaUrl,
          compact: true,
        ),
      ],
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
        ? 'In WhatsApp catalogue'
        : product.whatsappListed == false
            ? 'Not in WhatsApp catalogue'
            : 'Attached to campaign';
    final availabilityColor = product.whatsappListed == true
        ? Colors.green.shade700
        : product.whatsappListed == false
            ? Colors.orange.shade800
            : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 52,
              height: 52,
              child: product.imageUrl?.trim().isNotEmpty == true
                  ? Image.network(
                      product.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _ProductPlaceholder(
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : _ProductPlaceholder(color: theme.colorScheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Product',
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
                Row(
                  children: [
                    Icon(
                      product.whatsappListed == true
                          ? Icons.check_circle_outline_rounded
                          : product.whatsappListed == false
                              ? Icons.info_outline_rounded
                              : Icons.link_rounded,
                      color: availabilityColor,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        availability,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: availabilityColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (product.sellingPrice != null) ...[
            const SizedBox(width: 8),
            Text(
              CurrencyUtil.format(product.sellingPrice!),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductPlaceholder extends StatelessWidget {
  const _ProductPlaceholder({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color.withValues(alpha: 0.08),
      child: Icon(
        Icons.inventory_2_outlined,
        color: color,
        size: 22,
      ),
    );
  }
}
