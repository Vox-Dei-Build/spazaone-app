// promotions_tab.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/utils/run_promotion_launcher.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/run_promotion_page.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/promote/widgets/promotions/view_promotion/view_promotion.dart';
import 'package:pasella/shared/widgets/empty_state_onboarding.dart';
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
      return const Center(child: CircularProgressIndicator());
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
      // PAS-AUTH-03: align with Stock-style empty state. Primary CTA is
      // intentionally omitted — the parent `PromotionsPage` already
      // owns a "Run Promotion" FAB that runs the approved-templates
      // gate; a second button here would have to duplicate that
      // predicate (the exact mistake PAS-UX-09 was fixing). Tutorial
      // link uses the existing TUTORIAL_RUN_PROMOTIONS Remote Config
      // entry.
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: SizeConfig.heightMultiplier * 8),
            const EmptyStateOnboarding(
              icon: Icons.campaign_outlined,
              headline: 'No promotions yet',
              subtitle: 'Choose a WhatsApp-listed product, select customers, '
                  'review the cost and send. SpazaOne prepares the message.',
              tutorialKey: TutorialConfig.TUTORIAL_RUN_PROMOTIONS,
              tutorialTitle: 'How to run a promotion',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: promos.length,
        itemBuilder: (ctx, i) {
          final promo = promos[i];
          final created = (promo['createdAt'] as Timestamp).toDate();
          final date = DateFormat('MMM dd, yyyy').format(created);
          final status =
              sanitizeMalformedUtf16(promo['status'] as String? ?? '');
          // PAS-UX-11: 'saved' is the audit's saved-but-unsent state.
          // Surface it more strongly than the rest because every other
          // state on this list is terminal (processing/sent), but a
          // saved promotion is sitting there waiting for the merchant
          // to come back and pay+send. Without an explicit affordance
          // they were getting lost in the list.
          final isPendingSend = status == 'saved';
          final statusColor = isPendingSend
              ? Colors.blue
              : status == 'processing'
                  ? Colors.orange
                  : Colors.green;

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
          final total = promos.length;
          final displayIndex = total - i;
          final linkedProductValue = promo['linkedProduct'];
          final linkedProduct = linkedProductValue is Map<String, dynamic>
              ? LinkedProductRef.fromMap(linkedProductValue)
              : null;
          final name = sanitizeMalformedUtf16(
            linkedProduct?.name ?? template['name'] as String? ?? '–',
          );
          final mediaUrl =
              linkedProduct?.imageUrl ?? channels['whatsapp']?['mediaUrl'];

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ViewPromotionPage(viewModel: vm, promo: promo),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (mediaUrl != null && mediaUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          mediaUrl,
                          height: 80,
                          width: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image, size: 80),
                        ),
                      )
                    else
                      Container(
                        height: 80,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.description,
                            size: 40, color: Colors.grey),
                      ),
                    SizedBox(width: SizeConfig.imageSizeMultiplier * 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  sanitizeMalformedUtf16(
                                      'Promotion $displayIndex: $name'),
                                  style: TextStyle(
                                    fontSize: SizeConfig.textMultiplier * 1.8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // PAS-UX-11: pending-send chip. Inline
                              // 'Send now' is intentionally a tap on
                              // the whole card (which already opens
                              // the detail page where the existing
                              // WalletAffordabilityFooter handles the
                              // pay+send flow). A second tap target
                              // here would have to duplicate the
                              // affordability check, which the audit
                              // explicitly warned against.
                              if (isPendingSend)
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.blue.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.schedule_send,
                                            size: 12,
                                            color: Colors.blue.shade700),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            'Pending send',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.blue.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: SizeConfig.heightMultiplier * 0.3),
                          RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: SizeConfig.textMultiplier * 1.5,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge!
                                    .color,
                              ),
                              children: [
                                const TextSpan(text: "Status: "),
                                TextSpan(
                                  text: status.isNotEmpty
                                      ? sanitizeMalformedUtf16(
                                          '${status[0].toUpperCase()}${status.substring(1)}',
                                        )
                                      : status,
                                  style: TextStyle(color: statusColor),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: SizeConfig.heightMultiplier * 0.2),
                          Text(
                            "Date: $date",
                            style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 1.5,
                            ),
                          ),
                          if (linkedProduct != null) ...[
                            SizedBox(height: SizeConfig.heightMultiplier * 0.3),
                            Row(
                              children: [
                                Icon(
                                  Icons.inventory_2_outlined,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    linkedProduct.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: SizeConfig.textMultiplier * 1.4,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (isPendingSend) ...[
                            SizedBox(height: SizeConfig.heightMultiplier * 0.5),
                            Row(
                              children: [
                                Icon(Icons.send,
                                    size: 14, color: Colors.blue.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  'Tap to review and send',
                                  style: TextStyle(
                                    fontSize: SizeConfig.textMultiplier * 1.4,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (isTerminal) ...[
                            SizedBox(height: SizeConfig.heightMultiplier * 0.5),
                            // Use a constrained OutlinedButton rather
                            // than a full-width one — the card row is
                            // already crowded with the thumbnail and
                            // title, and we want the affordance
                            // present but not louder than the
                            // primary "tap card to view detail"
                            // interaction.
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed: () {
                                  // Clear any selection that may
                                  // belong to a previously-viewed
                                  // promo before pushing the wizard
                                  // so step 2 starts fresh — the
                                  // ViewPromotionPage flow does the
                                  // same thing.
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
                                      builder: (_) => RunPromotionPage(
                                        rerunFromPromo: promo,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.replay, size: 16),
                                label: const Text(
                                  'Run again',
                                  style: TextStyle(fontSize: 12.5),
                                ),
                              ),
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
        },
      ),
    );
  }
}
