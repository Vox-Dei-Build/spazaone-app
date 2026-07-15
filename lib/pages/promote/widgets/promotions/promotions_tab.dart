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
      // PAS-AUTH-03: align with Stock-style empty state. The host owns the
      // primary product CTA, so the history area does not add a competing
      // start for the same journey. The tutorial link uses the existing
      // TUTORIAL_RUN_PROMOTIONS Remote Config entry.
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
          final date = DateFormat('d MMM yyyy').format(created);
          final status =
              sanitizeMalformedUtf16(promo['status'] as String? ?? '');
          // PAS-UX-11: 'saved' is the audit's saved-but-unsent state.
          // Surface it more strongly than the rest because every other
          // state on this list is terminal (processing/sent), but a
          // saved promotion is sitting there waiting for the merchant
          // to come back and pay+send. Without an explicit affordance
          // they were getting lost in the list.
          final isPendingSend = status == 'saved';
          final statusLabel = status.isEmpty
              ? 'Unknown'
              : '${status[0].toUpperCase()}${status.substring(1)}';
          final statusStyle = _promotionStatusStyle(status);

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
          final theme = Theme.of(context);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE0E5E1)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
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
                padding: const EdgeInsets.all(10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (mediaUrl != null && mediaUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          mediaUrl,
                          height: 68,
                          width: 68,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 68,
                            width: 68,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      )
                    else
                      Container(
                        height: 68,
                        width: 68,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.campaign_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 8,
                            runSpacing: 5,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _PromotionStatusPill(
                                label: sanitizeMalformedUtf16(statusLabel),
                                style: statusStyle,
                              ),
                              Text(
                                date,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          if (isPendingSend) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Tap to review and send',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusStyle.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          if (isTerminal) ...[
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  minimumSize: const Size(44, 36),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
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
                                icon:
                                    const Icon(Icons.replay_rounded, size: 17),
                                label: const Text('Run again'),
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

class _PromotionStatusPill extends StatelessWidget {
  const _PromotionStatusPill({required this.label, required this.style});

  final String label;
  final _PromotionStatusStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 12, color: style.foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: style.foreground,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _PromotionStatusStyle {
  const _PromotionStatusStyle({
    required this.foreground,
    required this.background,
    required this.icon,
  });

  final Color foreground;
  final Color background;
  final IconData icon;
}

_PromotionStatusStyle _promotionStatusStyle(String status) {
  if (status == 'complete' || status == 'sent') {
    return _PromotionStatusStyle(
      foreground: Colors.green.shade800,
      background: Colors.green.shade50,
      icon: Icons.check_circle_outline_rounded,
    );
  }
  if (status == 'failed') {
    return _PromotionStatusStyle(
      foreground: Colors.red.shade800,
      background: Colors.red.shade50,
      icon: Icons.error_outline_rounded,
    );
  }
  if (status == 'partial' || status == 'processing') {
    return _PromotionStatusStyle(
      foreground: Colors.orange.shade900,
      background: Colors.orange.shade50,
      icon: status == 'processing'
          ? Icons.sync_rounded
          : Icons.info_outline_rounded,
    );
  }
  if (status == 'saved') {
    return _PromotionStatusStyle(
      foreground: Colors.blue.shade800,
      background: Colors.blue.shade50,
      icon: Icons.schedule_send_outlined,
    );
  }
  return _PromotionStatusStyle(
    foreground: Colors.grey.shade800,
    background: Colors.grey.shade200,
    icon: Icons.help_outline_rounded,
  );
}
