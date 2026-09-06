import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/review_and_pricing/review_and_pricing_step.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/utils/currency_util.dart';

/// Readable delivery totals for both current and legacy promotion documents.
///
/// Older promotions predate the persisted attempted/succeeded/failed fields,
/// so terminal states fall back to the original recipient count.
class PromotionDeliverySummary {
  const PromotionDeliverySummary({
    required this.recipients,
    required this.attempted,
    required this.succeeded,
    required this.failed,
  });

  final int recipients;
  final int attempted;
  final int succeeded;
  final int failed;

  factory PromotionDeliverySummary.fromPromo(Map<String, dynamic> promo) {
    final status = promo['status'] as String? ?? '';
    final recipientCount = (promo['customerIds'] as List?)?.length ?? 0;
    final attempted =
        (promo['attemptedCount'] as num?)?.toInt() ?? recipientCount;
    final explicitSucceeded = (promo['succeededCount'] as num?)?.toInt();
    final explicitFailed = (promo['failedCount'] as num?)?.toInt();

    final succeeded = explicitSucceeded ??
        (status == 'complete'
            ? attempted
            : status == 'partial'
                ? (attempted - (explicitFailed ?? 0)).clamp(0, attempted)
                : 0);
    final failed = explicitFailed ??
        (status == 'failed'
            ? attempted
            : status == 'partial'
                ? (attempted - succeeded).clamp(0, attempted)
                : 0);

    return PromotionDeliverySummary(
      recipients: recipientCount,
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
    );
  }
}

class PromotionDetailContent extends StatelessWidget {
  const PromotionDetailContent({
    super.key,
    required this.promo,
    required this.templateContent,
    required this.shopName,
    required this.estimatedCost,
    required this.customers,
    required this.selectedCustomerIds,
    this.mediaUrl,
  });

  final Map<String, dynamic> promo;
  final String? templateContent;
  final String shopName;
  final double estimatedCost;
  final List<Map<String, dynamic>> customers;
  final Set<String> selectedCustomerIds;
  final String? mediaUrl;

  @override
  Widget build(BuildContext context) {
    final status = promo['status'] as String? ?? '';
    final summary = PromotionDeliverySummary.fromPromo(promo);
    final product = _linkedProduct(promo['linkedProduct']);
    final actualCost = (promo['actualCost'] as num?)?.toDouble();
    final message = resolvePromotionPreviewContent(
      templateContent: templateContent,
      shopName: shopName,
      product: product,
    );
    final exampleRecipient = _firstRecipientName(
      customers,
      selectedCustomerIds,
    );
    final exampleMessage = exampleRecipient == null
        ? message
        : message.replaceAll('[Customer Name]', exampleRecipient);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        LayoutConstants.spaceLg,
        LayoutConstants.spaceMd,
        LayoutConstants.spaceLg,
        LayoutConstants.spaceXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusHero(
            promo: promo,
            status: status,
            summary: summary,
          ),
          if (product != null) ...[
            const SizedBox(height: LayoutConstants.spaceMd),
            _ProductSection(product: product),
          ],
          const SizedBox(height: LayoutConstants.spaceMd),
          _DeliverySection(
            promo: promo,
            summary: summary,
            cost: actualCost ?? estimatedCost,
            isEstimate: actualCost == null,
          ),
          const SizedBox(height: LayoutConstants.spaceMd),
          _MessageSection(
            message: exampleMessage,
            whatsappEnabled: promo['sendWhatsApp'] as bool? ?? false,
            smsEnabled: promo['sendSMS'] as bool? ?? false,
            imageUrl: _previewMediaUrl(product, mediaUrl),
            showOrderButton: product != null,
            exampleRecipient: exampleRecipient,
          ),
          const SizedBox(height: LayoutConstants.spaceMd),
          _RecipientsSection(
            customers: customers,
            selectedCustomerIds: selectedCustomerIds,
          ),
        ],
      ),
    );
  }
}

LinkedProductRef? _linkedProduct(Object? value) {
  if (value is! Map) return null;
  return LinkedProductRef.fromMap(Map<String, dynamic>.from(value));
}

String? _firstRecipientName(
  List<Map<String, dynamic>> customers,
  Set<String> selectedCustomerIds,
) {
  for (final customer in customers) {
    if (!selectedCustomerIds.contains(customer['id'])) continue;
    final name = (customer['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
  }
  return null;
}

String? _previewMediaUrl(LinkedProductRef? product, String? templateMediaUrl) {
  final productImage = product?.imageUrl?.trim();
  if (productImage != null && productImage.isNotEmpty) return productImage;
  final templateImage = templateMediaUrl?.trim();
  if (templateImage == null ||
      templateImage.isEmpty ||
      templateImage.contains('{{')) {
    return null;
  }
  return templateImage;
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({
    required this.promo,
    required this.status,
    required this.summary,
  });

  final Map<String, dynamic> promo;
  final String status;
  final PromotionDeliverySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _statusStyle(status);
    final date = _timestampDate(promo['completedAt']) ??
        _timestampDate(promo['createdAt']);
    final error = promo['lastErrorMessage'] as String?;

    return Container(
      padding: const EdgeInsets.all(LayoutConstants.spaceLg),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
        border: Border.all(color: style.foreground.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: style.foreground.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(style.icon, color: style.foreground, size: 25),
              ),
              const SizedBox(width: LayoutConstants.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      style.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: style.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusSummary(status, summary),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (date != null) ...[
            const SizedBox(height: LayoutConstants.spaceMd),
            Row(
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  DateFormat('d MMM yyyy • HH:mm').format(date),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          if ((status == 'failed' || status == 'partial') &&
              error != null &&
              error.trim().isNotEmpty) ...[
            const SizedBox(height: LayoutConstants.spaceMd),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(LayoutConstants.spaceMd),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                error.trim(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: style.foreground,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductSection extends StatelessWidget {
  const _ProductSection({required this.product});

  final LinkedProductRef product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _DetailCard(
      title: 'Product',
      icon: Icons.inventory_2_outlined,
      child: Row(
        children: [
          _ProductImage(product: product),
          const SizedBox(width: LayoutConstants.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (product.sellingPrice != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    CurrencyUtil.format(product.sellingPrice!),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      product.whatsappListed == true
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      size: 15,
                      color: product.whatsappListed == true
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        product.whatsappListed == true
                            ? 'Available for WhatsApp orders'
                            : 'Catalogue availability unknown',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: product.whatsappListed == true
                              ? Colors.green.shade700
                              : Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.product});

  final LinkedProductRef product;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.inventory_2_outlined),
    );
    if (product.imageUrl == null || product.imageUrl!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        product.imageUrl!,
        width: 68,
        height: 68,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _DeliverySection extends StatelessWidget {
  const _DeliverySection({
    required this.promo,
    required this.summary,
    required this.cost,
    required this.isEstimate,
  });

  final Map<String, dynamic> promo;
  final PromotionDeliverySummary summary;
  final double cost;
  final bool isEstimate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final whatsapp = promo['sendWhatsApp'] as bool? ?? false;
    final sms = promo['sendSMS'] as bool? ?? false;

    return _DetailCard(
      title: 'Delivery',
      icon: Icons.send_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Metric(
                  value: '${summary.recipients}',
                  label: 'Recipients',
                ),
              ),
              const _MetricDivider(),
              Expanded(
                child: _Metric(
                  value: '${summary.succeeded}',
                  label: 'Delivered',
                  valueColor: Colors.green,
                ),
              ),
              const _MetricDivider(),
              Expanded(
                child: _Metric(
                  value: '${summary.failed}',
                  label: 'Failed',
                  valueColor: summary.failed > 0 ? Colors.red : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: LayoutConstants.spaceMd),
          Wrap(
            spacing: LayoutConstants.spaceSm,
            runSpacing: LayoutConstants.spaceSm,
            children: [
              if (whatsapp)
                const _ChannelChip(
                  icon: Icons.chat_bubble_outline,
                  label: 'WhatsApp',
                ),
              if (sms)
                const _ChannelChip(
                  icon: Icons.sms_outlined,
                  label: 'SMS fallback',
                ),
            ],
          ),
          const SizedBox(height: LayoutConstants.spaceMd),
          const Divider(height: 1),
          const SizedBox(height: LayoutConstants.spaceMd),
          Row(
            children: [
              Expanded(
                child: Text(
                  isEstimate ? 'Estimated cost' : 'Campaign cost',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                CurrencyUtil.format(cost),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    this.valueColor,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: valueColor,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: VerticalDivider(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageSection extends StatelessWidget {
  const _MessageSection({
    required this.message,
    required this.whatsappEnabled,
    required this.smsEnabled,
    required this.imageUrl,
    required this.showOrderButton,
    required this.exampleRecipient,
  });

  final String message;
  final bool whatsappEnabled;
  final bool smsEnabled;
  final String? imageUrl;
  final bool showOrderButton;
  final String? exampleRecipient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _DetailCard(
      title: whatsappEnabled ? 'WhatsApp preview' : 'Message',
      icon: whatsappEnabled
          ? Icons.chat_bubble_outline_rounded
          : Icons.chat_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (exampleRecipient != null) ...[
            Text(
              'Example for $exampleRecipient',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: LayoutConstants.spaceSm),
          ],
          if (whatsappEnabled)
            _WhatsAppCardPreview(
              message: message,
              imageUrl: imageUrl,
              showOrderButton: showOrderButton,
            )
          else
            Container(
              padding: const EdgeInsets.all(LayoutConstants.spaceMd),
              decoration: BoxDecoration(
                color: SpazaColors.subtle,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
            ),
          if (smsEnabled) ...[
            const SizedBox(height: LayoutConstants.spaceSm),
            Text(
              'SMS was enabled as the automatic fallback.',
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

class _WhatsAppCardPreview extends StatelessWidget {
  const _WhatsAppCardPreview({
    required this.message,
    required this.imageUrl,
    required this.showOrderButton,
  });

  final String message;
  final String? imageUrl;
  final bool showOrderButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(LayoutConstants.spaceMd),
      decoration: BoxDecoration(
        color: WaBrandColour.chatBackground,
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: 0.94,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (imageUrl != null)
                  Image.network(
                    imageUrl!,
                    height: 150,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10, bottom: 6),
                  child: Text(
                    '12:00',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: WaBrandColour.time,
                    ),
                  ),
                ),
                if (showOrderButton) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.shopping_bag_outlined,
                          size: 18,
                          color: WaBrandColour.tealGreenLighter,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'Order on WhatsApp',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: WaBrandColour.tealGreenLighter,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecipientsSection extends StatelessWidget {
  const _RecipientsSection({
    required this.customers,
    required this.selectedCustomerIds,
  });

  final List<Map<String, dynamic>> customers;
  final Set<String> selectedCustomerIds;

  List<Map<String, dynamic>> get recipients => customers
      .where((customer) => selectedCustomerIds.contains(customer['id']))
      .toList();

  @override
  Widget build(BuildContext context) {
    final visible = recipients;
    final preview = visible.take(4).toList();

    return _DetailCard(
      title: 'Recipients',
      icon: Icons.people_alt_outlined,
      trailing: Text(
        '${selectedCustomerIds.length}',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
      ),
      child: Column(
        children: [
          if (preview.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                selectedCustomerIds.isEmpty
                    ? 'No recipients selected.'
                    : 'Recipient details are unavailable.',
              ),
            )
          else
            for (var index = 0; index < preview.length; index++) ...[
              _RecipientRow(customer: preview[index]),
              if (index != preview.length - 1) const Divider(height: 16),
            ],
          if (visible.length > preview.length) ...[
            const SizedBox(height: LayoutConstants.spaceSm),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => _showAll(context, visible),
                child: Text('View all ${visible.length} recipients'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAll(
    BuildContext context,
    List<Map<String, dynamic>> visible,
  ) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '${visible.length} recipients',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(LayoutConstants.spaceLg),
                itemCount: visible.length,
                separatorBuilder: (_, __) => const Divider(height: 18),
                itemBuilder: (_, index) =>
                    _RecipientRow(customer: visible[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({required this.customer});

  final Map<String, dynamic> customer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (customer['name'] as String?)?.trim();
    final displayName = name == null || name.isEmpty ? 'Customer' : name;
    final number = (customer['number'] as String?)?.trim() ?? '';

    return Row(
      children: [
        ProfileImageWidget(
          imageUrl: customer['profileImageUrl'] as String?,
          initials: displayName,
          radius: 19,
        ),
        const SizedBox(width: LayoutConstants.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (number.isNotEmpty)
                Text(
                  number,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(LayoutConstants.spaceLg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
        border: Border.all(color: SpazaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: LayoutConstants.spaceSm),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: LayoutConstants.spaceMd),
          child,
        ],
      ),
    );
  }
}

DateTime? _timestampDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

String _statusSummary(String status, PromotionDeliverySummary summary) {
  if (status == 'saved') {
    return 'Ready for ${summary.recipients} '
        'recipient${summary.recipients == 1 ? '' : 's'}.';
  }
  if (status == 'processing') return 'Sending is in progress.';
  if (status == 'complete') {
    return '${summary.succeeded} of ${summary.attempted} messages delivered.';
  }
  if (status == 'partial') {
    return '${summary.succeeded} delivered • ${summary.failed} failed.';
  }
  if (status == 'failed') return 'No messages were delivered.';
  return '${summary.recipients} '
      'recipient${summary.recipients == 1 ? '' : 's'}.';
}

class _PromotionStatusStyle {
  const _PromotionStatusStyle({
    required this.title,
    required this.foreground,
    required this.background,
    required this.icon,
  });

  final String title;
  final Color foreground;
  final Color background;
  final IconData icon;
}

_PromotionStatusStyle _statusStyle(String status) {
  if (status == 'complete') {
    return _PromotionStatusStyle(
      title: 'Campaign sent',
      foreground: Colors.green.shade800,
      background: const Color(0xFFF1F8F3),
      icon: Icons.check_circle_outline_rounded,
    );
  }
  if (status == 'failed') {
    return _PromotionStatusStyle(
      title: 'Campaign failed',
      foreground: Colors.red.shade800,
      background: const Color(0xFFFFF3F3),
      icon: Icons.error_outline_rounded,
    );
  }
  if (status == 'partial') {
    return _PromotionStatusStyle(
      title: 'Partially sent',
      foreground: Colors.orange.shade900,
      background: const Color(0xFFFFF7EC),
      icon: Icons.info_outline_rounded,
    );
  }
  if (status == 'processing') {
    return _PromotionStatusStyle(
      title: 'Sending campaign',
      foreground: Colors.orange.shade900,
      background: const Color(0xFFFFF7EC),
      icon: Icons.sync_rounded,
    );
  }
  if (status == 'saved') {
    return _PromotionStatusStyle(
      title: 'Ready to send',
      foreground: Colors.blue.shade800,
      background: const Color(0xFFF2F6FC),
      icon: Icons.schedule_send_outlined,
    );
  }
  return _PromotionStatusStyle(
    title: 'Campaign details',
    foreground: Colors.grey.shade800,
    background: const Color(0xFFF5F5F5),
    icon: Icons.campaign_outlined,
  );
}
