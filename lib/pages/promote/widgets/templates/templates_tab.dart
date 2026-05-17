import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/utils/template_status.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/templates/view_template/template_detail_page.dart';
import 'package:pasella/utils/text_sanitizer.dart';
import 'package:provider/provider.dart';

class TemplatesTab extends StatefulWidget {
  const TemplatesTab({Key? key}) : super(key: key);

  @override
  State<TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends State<TemplatesTab> {
  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<PromotionsViewModel>(context);

    if (viewModel.loadingTemplates) {
      return const Center(child: CircularProgressIndicator());
    }

    final templates = viewModel.templates;

    if (templates.isEmpty) {
      return const _EmptyState();
    }

    // Tally states for the summary banner.
    final pendingCount = templates
        .where((t) => templateStatusOf(t) == TemplateStatus.pending)
        .length;
    final rejectedCount = templates
        .where((t) => templateStatusOf(t) == TemplateStatus.rejected)
        .length;
    final failedCount = templates
        .where((t) => templateStatusOf(t) == TemplateStatus.submissionFailed)
        .length;

    return RefreshIndicator(
      onRefresh: viewModel.loadTemplatesData,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          if (pendingCount > 0 || rejectedCount > 0 || failedCount > 0)
            _StatusSummary(
              pending: pendingCount,
              rejected: rejectedCount,
              failed: failedCount,
            ),
          ...templates.map((t) => _TemplateCard(
                template: t,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TemplateDetailPage(
                        viewModel: viewModel,
                        template: t,
                        shopName: viewModel.shopName,
                        whatsappPrice: viewModel.whatsappPrice,
                        smsPricePerSegment: viewModel.smsPricePerSegment,
                      ),
                    ),
                  );
                },
              )),
        ],
      ),
    );
  }
}

// ─── Empty state ────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_books_outlined,
                size: 64, color: theme.disabledColor),
            const SizedBox(height: 16),
            Text(
              'No templates yet',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Templates are pre-approved messages you can send to your customers. Tap "Create Template" below to get started.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.disabledColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Summary banner ─────────────────────────────────────────────────────────
class _StatusSummary extends StatelessWidget {
  final int pending;
  final int rejected;
  final int failed;

  const _StatusSummary({
    required this.pending,
    required this.rejected,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <_SummaryPart>[];
    if (pending > 0) {
      parts.add(_SummaryPart(
        icon: Icons.hourglass_top,
        color: Colors.amber.shade700,
        text:
            '$pending ${pending == 1 ? 'template' : 'templates'} awaiting WhatsApp approval. We\'ll notify you the moment it\'s ready.',
      ));
    }
    if (rejected > 0) {
      parts.add(_SummaryPart(
        icon: Icons.cancel_outlined,
        color: Colors.red,
        text:
            '$rejected rejected. Tap a rejected template to see the reason and resubmit.',
      ));
    }
    if (failed > 0) {
      parts.add(_SummaryPart(
        icon: Icons.warning_amber_rounded,
        color: Colors.deepOrange,
        text: '$failed couldn\'t be submitted to WhatsApp. Tap to retry.',
      ));
    }
    if (parts.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < parts.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(parts[i].icon, color: parts[i].color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    parts[i].text,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (i < parts.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _SummaryPart {
  final IconData icon;
  final Color color;
  final String text;
  const _SummaryPart(
      {required this.icon, required this.color, required this.text});
}

// ─── Card ───────────────────────────────────────────────────────────────────
class _TemplateCard extends StatelessWidget {
  final Map<String, dynamic> template;
  final VoidCallback onTap;

  const _TemplateCard({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = templateStatusOf(template);
    final reason = templateFailureReason(template);
    final submittedAt = templateSubmittedAt(template);

    final displayName = sanitizeMalformedUtf16(
        (template['displayName'] ?? template['name'] ?? 'Untitled').toString());
    final channels = template['channels'] as Map<String, dynamic>? ?? {};
    final channelKeys = sanitizeMalformedUtf16(
        channels.keys.map((k) => k.toUpperCase()).join(' • '));
    final mediaUrl = channels['whatsapp']?['mediaUrl'];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              if (mediaUrl != null && mediaUrl.toString().isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    mediaUrl,
                    height: 72,
                    width: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image, size: 72),
                  ),
                )
              else
                Container(
                  height: 72,
                  width: 72,
                  decoration: BoxDecoration(
                    color: status.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(status.icon, size: 32, color: status.color),
                ),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(child: _StatusPill(status: status)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(channelKeys, style: theme.textTheme.bodySmall),
                    if (submittedAt != null)
                      Text(
                        status == TemplateStatus.approved
                            ? 'Approved • ${DateFormat('MMM d').format(submittedAt)}'
                            : status == TemplateStatus.pending
                                ? 'Submitted ${relativeTime(submittedAt)}'
                                : status == TemplateStatus.rejected
                                    ? 'Rejected • ${DateFormat('MMM d').format(submittedAt)}'
                                    : DateFormat('MMM d, yyyy')
                                        .format(submittedAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.disabledColor,
                        ),
                      ),
                    if (reason != null && status != TemplateStatus.approved)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: status.color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline,
                                  size: 14, color: status.color),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  status == TemplateStatus.rejected
                                      ? 'Reason: $reason'
                                      : reason,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: status.color,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final TemplateStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: status.color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 12, color: status.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              status.label,
              style: TextStyle(
                color: status.color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
