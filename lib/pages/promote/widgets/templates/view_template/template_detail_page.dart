import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/utils/run_promotion_launcher.dart';
import 'package:pasella/pages/promote/utils/template_status.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/confirmation_dialog.dart';
import 'package:pasella/pages/promote/widgets/message_preview_card.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/create_template.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

class TemplateDetailPage extends StatefulWidget {
  final PromotionsViewModel viewModel;
  final Map<String, dynamic> template;
  final String shopName;
  final double? whatsappPrice;
  final double? smsPricePerSegment;

  const TemplateDetailPage({
    Key? key,
    required this.viewModel,
    required this.template,
    required this.shopName,
    required this.whatsappPrice,
    required this.smsPricePerSegment,
  }) : super(key: key);

  @override
  State<TemplateDetailPage> createState() => _TemplateDetailPageState();
}

class _TemplateDetailPageState extends State<TemplateDetailPage> {
  bool _actionLoading = false;

  String _resolvedMessage(String content) {
    return content
        .replaceAll('{{customerName}}', '[Customer Name]')
        .replaceAll('{{shopName}}', widget.shopName);
  }

  Future<void> _deleteTemplate() async {
    setState(() => _actionLoading = true);
    final templateId = widget.template['id'];
    final success =
        await widget.viewModel.deleteTemplate(templateId, widget.template);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Template deleted successfully'
            : 'Failed to delete template'),
      ),
    );
    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() => _actionLoading = false);
    }
  }

  /// PAS-UX-06: jump from template preview straight into the
  /// promotion wizard with this template pre-selected.
  ///
  /// The detail page stays in the navigation stack underneath. If
  /// the merchant cancels the wizard they land back on the template
  /// they were considering, which matches the mental model "I was
  /// previewing this and changed my mind". On successful send the
  /// wizard pops itself; the merchant is back on the detail page
  /// and a single back tap returns them to Templates. We don't
  /// auto-pop the detail because we deliberately don't want to
  /// strip context from a merchant who might want to read the
  /// preview again before sending to a different segment.
  Future<void> _useThisTemplate() async {
    final templateId = widget.template['id']?.toString();
    if (templateId == null || templateId.isEmpty) return;
    await RunPromotionLauncher.launch(
      context,
      viewModel: widget.viewModel,
      initialTemplateId: templateId,
    );
  }

  /// Opens the Create Template wizard pre-filled with this template's
  /// content. Twilio doesn't allow editing a submitted template — under the
  /// hood this creates a new submission, but to the user it feels like an
  /// edit-and-resubmit. After successful submission we delete the failed
  /// original so the list stays tidy.
  Future<void> _fixAndResubmit() async {
    final wa = widget.template['channels']?['whatsapp'] as Map<String, dynamic>?;
    final sms = widget.template['channels']?['sms'] as Map<String, dynamic>?;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateTemplatePage(
          viewModel: widget.viewModel,
          prefill: TemplatePrefill(
            displayName:
                (widget.template['displayName'] ?? widget.template['name'] ?? '')
                    .toString(),
            whatsappContent: (wa?['templateContent'] ?? '').toString(),
            smsContent: (sms?['templateContent'] ?? '').toString(),
            mediaUrl: (wa?['mediaUrl'] ?? '').toString(),
            includeWhatsApp: wa != null,
            includeSMS: sms != null,
            rejectionReason: templateFailureReason(widget.template),
          ),
        ),
      ),
    );

    if (result == true && mounted) {
      // The new submission lives independently. Delete the old rejected /
      // failed entry so the merchant's library doesn't accumulate dead docs.
      await widget.viewModel
          .deleteTemplate(widget.template['id'], widget.template);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final name = (t['displayName'] ?? t['name'] ?? 'Untitled').toString();
    final channels = t['channels'] as Map<String, dynamic>? ?? {};
    final createdAt = t['createdAt']?.toDate() as DateTime?;
    final formattedDate = createdAt != null
        ? DateFormat('MMM dd, yyyy – hh:mm a').format(createdAt)
        : 'Unknown';

    final whatsapp = channels['whatsapp'] as Map<String, dynamic>?;
    final sms = channels['sms'] as Map<String, dynamic>?;
    final smsSegments = sms != null
        ? SMSPricingUtil.calculateSegments(
            sms['templateContent'] as String? ?? '')
        : 1;

    final status = templateStatusOf(t);
    final reason = templateFailureReason(t);

    final pageContent = Scaffold(
      appBar: CustomAppBar(
        title: 'Template: $name',
        trailing: IconButton(
          icon: Icon(Icons.delete, size: SizeConfig.imageSizeMultiplier * 5),
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => ConfirmationDialog(
                title: 'Delete Template',
                message: 'Are you sure you want to delete this template?',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                onConfirm: () {
                  Navigator.of(context).pop();
                  _deleteTemplate();
                },
              ),
            );
          },
        ),
      ),
      body: ListView(
        padding: LayoutConstants.padding10Horizontal,
        children: [
          // Status banner ─────────────────────────────────────────────
          if (whatsapp != null) _StatusBanner(status: status, reason: reason),
          if (whatsapp != null &&
              (status == TemplateStatus.rejected ||
                  status == TemplateStatus.submissionFailed))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _fixAndResubmit,
                  icon: const Icon(Icons.refresh),
                  label: Text(status == TemplateStatus.submissionFailed
                      ? 'Retry submission'
                      : 'Fix and resubmit'),
                ),
              ),
            ),
          // PAS-UX-06: "Use this template" momentum shortcut.
          //
          // Audit found the Templates tab was a dead-end: a merchant
          // browsing templates and deciding "I want to send this one"
          // had to back out, switch to the Promotions tab, tap the
          // FAB, and re-pick the same template from a dropdown. The
          // launcher now accepts an initialTemplateId so we can drop
          // the merchant straight into the wizard with their choice
          // already selected. Approved-only because non-approved
          // templates can't be sent (the no-approved dialog would
          // bounce them right back).
          if (status.isUsable)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _useThisTemplate,
                  icon: const Icon(Icons.send),
                  label: const Text('Use this template'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          SizedBox(height: SizeConfig.heightMultiplier * 2),
          Text('Created: $formattedDate', textAlign: TextAlign.center),
          SizedBox(height: SizeConfig.heightMultiplier * 2),
          if (whatsapp != null) ...[
            const Text('WhatsApp Preview',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold)),
            if (widget.whatsappPrice != null)
              Text(
                'WhatsApp Cost: R${widget.whatsappPrice!.toStringAsFixed(2)} per recipient',
                textAlign: TextAlign.center,
              ),
            MessagePreviewCard(
              content: _resolvedMessage(
                  (whatsapp['templateContent'] ?? '').toString()),
              mediaUrl: whatsapp['mediaUrl'],
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 4),
          ],
          if (sms != null) ...[
            const Text('SMS Preview',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold)),
            if (widget.smsPricePerSegment != null)
              Text(
                'SMS Cost: R${(smsSegments * widget.smsPricePerSegment!).toStringAsFixed(2)} per recipient',
                textAlign: TextAlign.center,
              ),
            MessagePreviewCard(
              content: _resolvedMessage(
                  (sms['templateContent'] ?? '').toString()),
            ),
          ],
        ],
      ),
    );

    return Stack(
      children: [
        pageContent,
        if (_actionLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.4),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final TemplateStatus status;
  final String? reason;

  const _StatusBanner({required this.status, this.reason});

  String get _headline {
    switch (status) {
      case TemplateStatus.approved:
        return 'Approved by WhatsApp';
      case TemplateStatus.pending:
        return 'Awaiting WhatsApp approval';
      case TemplateStatus.rejected:
        return 'Rejected by WhatsApp';
      case TemplateStatus.submissionFailed:
        return 'Couldn\'t submit to WhatsApp';
      case TemplateStatus.draft:
        return 'Draft';
      case TemplateStatus.unknown:
        return 'Status unknown';
    }
  }

  String get _body {
    switch (status) {
      case TemplateStatus.approved:
        return 'Ready to use in promotions.';
      case TemplateStatus.pending:
        return 'Most templates are approved within minutes. Occasionally it takes up to 24 hours. We\'ll notify you the moment it\'s ready.';
      case TemplateStatus.rejected:
        return reason != null
            ? 'Reason: $reason'
            : 'No reason was provided. Tweak the wording and resubmit.';
      case TemplateStatus.submissionFailed:
        return reason != null
            ? 'Error: $reason'
            : 'Something went wrong on our side. Tap retry below.';
      case TemplateStatus.draft:
        return 'This template hasn\'t been submitted yet.';
      case TemplateStatus.unknown:
        return 'Reach out to support if this persists.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: status.color.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(status.icon, color: status.color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _headline,
                  style: TextStyle(
                    color: status.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _body,
                  style: TextStyle(
                    color: status.color.withOpacity(0.85),
                    fontSize: 12.5,
                    height: 1.35,
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
