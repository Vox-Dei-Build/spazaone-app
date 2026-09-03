import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
    final snapshot = controller.snapshot;
    if (!controller.enabled) return const SizedBox.shrink();
    if (snapshot == null) {
      return Card(
        key: const ValueKey('whatsapp-catalog-status-unavailable'),
        margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
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
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
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
                          fontWeight: FontWeight.w800,
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
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      );
}
