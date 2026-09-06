// promotions_tab.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/utils/run_promotion_launcher.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/run_promotion_page.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/promote/widgets/promotions/view_promotion/view_promotion.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pasella/utils/text_sanitizer.dart';

class PromotionsTab extends StatefulWidget {
  const PromotionsTab({Key? key}) : super(key: key);

  @override
  State<PromotionsTab> createState() => _PromotionsTabState();
}

class _PromotionsTabState extends State<PromotionsTab> {
  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<PromotionsViewModel>(context);
    if (vm.loadingPromotions) {
      return const Center(
          child:
              CircularProgressIndicator(semanticsLabel: 'Loading promotions'));
    }
    final promos = vm.promotionsReports;

    // Wrap in a RefreshIndicator so merchants have a familiar way to
    // force-refresh while waiting on backend state (promotion status
    // moving from 'processing' to 'sent', template approval flipping
    // upstream of the next automatic reload, etc.). The pull pulls
    // both the templates list and the promotions list so the names
    // shown against each promo card stay in sync.
    Future<void> onRefresh() async {
      await Future.wait([
        vm.fetchPromotionsReports(),
        vm.loadTemplatesData(),
      ]);
    }

    if (promos.isEmpty) {
      final theme = Theme.of(context);
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Icon(Icons.campaign_outlined,
                size: 32, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No campaigns yet',
                textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: promos.length,
        itemBuilder: (ctx, i) {
          final promo = promos[i];
          final created = (promo['createdAt'] as Timestamp).toDate();
          final date = DateFormat('d MMM yyyy').format(created);
          final status =
              sanitizeMalformedUtf16(promo['status'] as String? ?? '');
          // PAS-UX-18: terminal promotions (complete/partial/failed)
          // get an inline "Run again" affordance so the merchant
          // doesn't have to open the detail view and scroll just to
          // re-launch the same campaign. Saved/processing promos are
          // intentionally excluded — saved already has its own
          // pending-send affordance, processing is in flight.
          final isTerminal =
              status.isNotEmpty && status != 'saved' && status != 'processing';

          // lookup template name
          final templateId = promo['templateId'] as String;
          final template = vm.templates.firstWhere(
            (t) => t['id'] == templateId,
            orElse: () => {},
          );

          final channels = template['channels'] as Map<String, dynamic>? ?? {};
          final linkedProductValue = promo['linkedProduct'];
          final linkedProduct = linkedProductValue is Map<String, dynamic>
              ? LinkedProductRef.fromMap(linkedProductValue)
              : null;
          final name = sanitizeMalformedUtf16(
            linkedProduct?.name ?? template['name'] as String? ?? '–',
          );
          final mediaUrl =
              linkedProduct?.imageUrl ?? channels['whatsapp']?['mediaUrl'];
          return PromotionHistoryCard(
            key: ValueKey(promo['id'] ?? i),
            name: name,
            dateLabel: date,
            status: status,
            imageUrl: mediaUrl is String ? mediaUrl : null,
            onOpen: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ViewPromotionPage(viewModel: vm, promo: promo),
              ),
            ),
            onRunAgain: isTerminal
                ? () {
                    vm.clearCustomerSelection();
                    if (linkedProduct != null) {
                      RunPromotionLauncher.launch(
                        context,
                        viewModel: vm,
                        initialProduct: linkedProduct,
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RunPromotionPage(rerunFromPromo: promo),
                      ),
                    );
                  }
                : null,
          );
        },
      ),
    );
  }
}

/// Campaign identity and delivery state, independent of loading and navigation.
class PromotionHistoryCard extends StatelessWidget {
  const PromotionHistoryCard({
    super.key,
    required this.name,
    required this.dateLabel,
    required this.status,
    required this.onOpen,
    this.imageUrl,
    this.onRunAgain,
  });

  final String name;
  final String dateLabel;
  final String status;
  final String? imageUrl;
  final VoidCallback onOpen;
  final VoidCallback? onRunAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusLabel = status.isEmpty
        ? 'Unknown'
        : '${status[0].toUpperCase()}${status.substring(1)}';
    final statusColor = status == 'failed'
        ? colors.error
        : status == 'complete' || status == 'sent'
            ? colors.primary
            : colors.onSurfaceVariant;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(Icons.campaign_outlined,
          size: 22, color: colors.onSurfaceVariant),
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(SpazaRadius.small),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: imageUrl?.isNotEmpty == true
                      ? Image.network(imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => placeholder)
                      : placeholder,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: Text(name,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700))),
                        const SizedBox(width: 8),
                        Icon(SpazaIcons.next,
                            size: 20, color: colors.onSurfaceVariant),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(sanitizeMalformedUtf16(statusLabel),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w500)),
                        Text(dateLabel,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ),
                    if (status == 'saved') ...[
                      const SizedBox(height: 8),
                      Text('Tap to review and send',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.secondary)),
                    ],
                    if (onRunAgain != null) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: onRunAgain,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 12),
                        ),
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text('Run again'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
