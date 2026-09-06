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

/// Status counts and a single refresh action, without onboarding copy.
class _CatalogStatusDetails extends StatelessWidget {
  const _CatalogStatusDetails({required this.controller});

  final WhatsAppCatalogStatusController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.enabled) return const SizedBox.shrink();
    final snapshot = controller.snapshot;
    final theme = Theme.of(context);
    final rolloutEnabled = snapshot?.rollout == WhatsAppCatalogRollout.enabled;
    return Column(
      key: ValueKey(snapshot == null
          ? 'whatsapp-catalog-status-unavailable'
          : 'whatsapp-catalog-status-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('WhatsApp catalogue',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: SpazaColors.heading,
                    fontWeight: FontWeight.w600,
                  )),
            ),
            IconButton(
              tooltip: 'Close catalogue status',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(SpazaIcons.close),
            ),
          ],
        ),
        if (snapshot == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              controller.loading
                  ? 'Checking status…'
                  : controller.errorMessage ??
                      'Couldn’t check status. Use Refresh status to try again.',
            ),
          )
        else if (!rolloutEnabled) ...[
          const SizedBox(height: 8),
          const Text('Not available for this shop yet.'),
          if (snapshot.summary.eligible > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${snapshot.summary.eligible} listing request${snapshot.summary.eligible == 1 ? '' : 's'} saved.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
        ] else ...[
          _StatusCount(label: 'Live on WhatsApp', value: snapshot.summary.live),
          _StatusCount(label: 'Syncing', value: snapshot.summary.syncing),
          _StatusCount(
              label: 'Needs attention', value: snapshot.summary.needsAttention),
          if (snapshot.summary.removalSyncing > 0)
            _StatusCount(
                label: 'Removing', value: snapshot.summary.removalSyncing),
        ],
        if (snapshot != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '${controller.isStale || snapshot.fromCache ? 'Last checked' : 'Checked'} '
              '${DateFormat('d MMM, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(snapshot.checkedAtMs))}',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: SpazaColors.muted),
            ),
          ),
        if (snapshot != null && controller.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(controller.errorMessage!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: SpazaColors.muted)),
          ),
        Tooltip(
          message: 'Refresh catalogue status',
          child: OutlinedButton.icon(
            onPressed: !controller.loading && controller.canManualRefresh
                ? controller.manualRefresh
                : null,
            icon: controller.loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 20),
            label: Text(controller.loading ? 'Checking…' : 'Refresh status'),
          ),
        ),
      ],
    );
  }
}

class _StatusCount extends StatelessWidget {
  const _StatusCount({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
                child:
                    Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            const SizedBox(width: 16),
            Text('$value',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: SpazaColors.heading,
                    )),
          ],
        ),
      );
}
