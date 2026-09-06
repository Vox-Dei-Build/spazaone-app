import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/models/stock/whatsapp_catalog_status.dart';
import 'package:pasella/services/whatsapp_catalog_status_service.dart';

class WhatsAppCatalogStatusCard extends StatelessWidget {
  const WhatsAppCatalogStatusCard({
    super.key,
    required this.controller,
  });

  final WhatsAppCatalogStatusController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.enabled) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('whatsapp-catalog-status-entry'),
        borderRadius: BorderRadius.circular(SpazaRadius.small),
        onTap: () => _openDetails(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(SpazaIcons.shop, size: 20, color: SpazaColors.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('WhatsApp catalogue',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: SpazaColors.ink,
                            fontWeight: FontWeight.w500,
                          )),
                      const SizedBox(height: 2),
                      Text(
                        _summary(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: SpazaColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(SpazaIcons.next, size: 18, color: SpazaColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _summary() {
    if (controller.loading) return 'Checking status…';
    final snapshot = controller.snapshot;
    if (snapshot == null) return 'Status unavailable';
    if (snapshot.rollout != WhatsAppCatalogRollout.enabled) {
      return 'Listing not enabled yet';
    }
    final summary = snapshot.summary;
    final counts = [
      '${summary.live} live',
      if (summary.syncing > 0) '${summary.syncing} syncing',
      if (summary.needsAttention > 0)
        '${summary.needsAttention} need attention',
      if (summary.removalSyncing > 0)
        '${summary.removalSyncing} removal${summary.removalSyncing == 1 ? '' : 's'} syncing',
    ].join(' · ');
    return controller.isStale || snapshot.fromCache
        ? 'Last checked: $counts'
        : counts;
  }

  void _openDetails(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: AnimatedBuilder(
              animation: controller,
              builder: (_, __) => _CatalogStatusDetails(controller: controller),
            ),
          ),
        ),
      ),
    );
  }
}

/// The full status, refresh action and guidance stay available on demand.
class _CatalogStatusDetails extends StatelessWidget {
  const _CatalogStatusDetails({required this.controller});

  final WhatsAppCatalogStatusController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    if (!controller.enabled) return const SizedBox.shrink();
    if (snapshot == null) {
      return Card(
        key: const ValueKey('whatsapp-catalog-status-unavailable'),
        margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: ListTile(
          leading: controller.loading
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_off_outlined),
          title: Text(
            controller.loading
                ? 'Checking WhatsApp catalogue…'
                : 'Catalogue status unavailable',
          ),
          subtitle: controller.loading
              ? null
              : Text(controller.errorMessage ?? 'Pull to refresh and retry.'),
          trailing: controller.loading
              ? null
              : IconButton(
                  tooltip: 'Refresh catalogue status',
                  onPressed: controller.canManualRefresh
                      ? controller.manualRefresh
                      : null,
                  icon: const Icon(Icons.refresh),
                ),
        ),
      );
    }
    final summary = snapshot.summary;
    final rolloutEnabled = snapshot.rollout == WhatsAppCatalogRollout.enabled;
    return Card(
      key: const ValueKey('whatsapp-catalog-status-summary'),
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront_outlined, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'WhatsApp catalogue',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh catalogue status',
                  onPressed: controller.canManualRefresh
                      ? controller.manualRefresh
                      : null,
                  icon: controller.loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            if (!rolloutEnabled) ...[
              Text(
                'Catalogue rollout is not yet enabled for this shop.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (summary.eligible > 0)
                Text(
                  '${summary.eligible} product${summary.eligible == 1 ? '' : 's'} requested for WhatsApp listing.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ] else ...[
              Text(
                'Catalogue delivery is enabled for this shop.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _Metric(label: 'Live', value: summary.live)),
                  Expanded(
                    child: _Metric(label: 'Syncing', value: summary.syncing),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'Needs attention',
                      value: summary.needsAttention,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _guidance(summary.live),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (summary.removalSyncing > 0)
                Text(
                  '${summary.removalSyncing} removal request${summary.removalSyncing == 1 ? '' : 's'} syncing.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            const SizedBox(height: 6),
            Text(
              '${controller.isStale || snapshot.fromCache ? 'Last checked' : 'Checked'} '
              '${DateFormat('d MMM, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(snapshot.checkedAtMs))}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (controller.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  controller.errorMessage!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _guidance(int live) {
    if (live < 5) {
      return 'Add ${5 - live} more valid product${5 - live == 1 ? '' : 's'} to reach a five-product view.';
    }
    if (live < 10) {
      return 'Ready for WhatsApp browsing. Add ${10 - live} more for a ten-product view.';
    }
    return 'Customers can browse 10 products at a time and continue to see more.';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label products: $value',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      );
}
