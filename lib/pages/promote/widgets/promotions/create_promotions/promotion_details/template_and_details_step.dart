import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/widgets/message_preview_card.dart';
import 'package:pasella/pages/promote/widgets/templates/template_picker_card.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

/// Step 1 of the Run Promotion wizard.
///
/// Lets the merchant pick a template (card list with status pills + in-flow
/// "create new template" CTA) and choose channels (WhatsApp default ON, SMS
/// opt-in). Shows pricing inline and a single unified preview with a channel
/// toggle so the same content isn't duplicated.
class TemplateAndDetailsStep extends StatefulWidget {
  final String? selectedTemplateId;
  final ValueChanged<String?> onTemplateChanged;
  final bool sendWhatsApp;
  final bool sendSMS;
  final ValueChanged<bool> onWhatsAppChanged;
  final ValueChanged<bool> onSMSChanged;
  final List<Map<String, dynamic>> templates;
  final String shopName;
  final double? whatsappPrice;
  final double? smsPricePerSegment;
  final VoidCallback onCreateTemplate;

  const TemplateAndDetailsStep({
    super.key,
    required this.selectedTemplateId,
    required this.onTemplateChanged,
    required this.sendWhatsApp,
    required this.sendSMS,
    required this.onWhatsAppChanged,
    required this.onSMSChanged,
    required this.templates,
    required this.shopName,
    required this.whatsappPrice,
    required this.smsPricePerSegment,
    required this.onCreateTemplate,
  });

  @override
  State<TemplateAndDetailsStep> createState() => _TemplateAndDetailsStepState();
}

enum _PreviewChannel { whatsapp, sms }

class _TemplateAndDetailsStepState extends State<TemplateAndDetailsStep> {
  _PreviewChannel _previewChannel = _PreviewChannel.whatsapp;

  String _renderPreview(String raw) {
    return raw
        .replaceAll('{{customerName}}', '[Customer Name]')
        .replaceAll('{{shopName}}', widget.shopName);
  }

  Map<String, dynamic>? get _selectedTemplate {
    if (widget.selectedTemplateId == null) return null;
    for (final t in widget.templates) {
      if (t['id'] == widget.selectedTemplateId) return t;
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant TemplateAndDetailsStep old) {
    super.didUpdateWidget(old);
    // Keep preview channel valid: if the active channel is toggled off, fall
    // back to whichever is still selected.
    if (_previewChannel == _PreviewChannel.whatsapp && !widget.sendWhatsApp) {
      _previewChannel = _PreviewChannel.sms;
    } else if (_previewChannel == _PreviewChannel.sms && !widget.sendSMS) {
      _previewChannel = _PreviewChannel.whatsapp;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTemplates = widget.templates.isNotEmpty;
    final approvedCount = widget.templates
        .where((t) => t['channels']?['whatsapp']?['approved'] == true)
        .length;
    final hasApproved = approvedCount > 0;

    final selected = _selectedTemplate;
    final waContent =
        (selected?['channels']?['whatsapp']?['templateContent'] ?? '')
            .toString();
    final smsContent =
        (selected?['channels']?['sms']?['templateContent'] ?? waContent)
            .toString();
    final mediaUrl = selected?['channels']?['whatsapp']?['mediaUrl'] as String?;
    final smsSegments = smsContent.isNotEmpty
        ? SMSPricingUtil.calculateSegments(smsContent)
        : 1;

    final noChannelsChosen = !widget.sendWhatsApp && !widget.sendSMS;

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 3,
        vertical: SizeConfig.heightMultiplier * 1,
      ),
      children: [
        // ── Section: Template ────────────────────────────────────────────
        _SectionHeader(
          title: 'Choose a template',
          subtitle: hasTemplates
              ? 'Pick the message you want to send.'
              : 'Create your first template to get started.',
          trailing: hasTemplates
              ? TextButton.icon(
                  onPressed: widget.onCreateTemplate,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 8),
        if (!hasTemplates)
          _EmptyTemplatesState(onCreate: widget.onCreateTemplate)
        else ...[
          if (!hasApproved)
            _InlineNotice(
              icon: Icons.hourglass_top,
              color: Colors.orange,
              message:
                  'Your templates are awaiting WhatsApp approval. They\'ll be selectable once approved.',
            ),
          ...widget.templates.map(
            (t) => TemplatePickerCard(
              template: t,
              selected: t['id'] == widget.selectedTemplateId,
              onTap: () => widget.onTemplateChanged(t['id'] as String?),
            ),
          ),
        ],

        SizedBox(height: SizeConfig.heightMultiplier * 3),

        // ── Section: Channels ────────────────────────────────────────────
        _SectionHeader(
          title: 'Choose channels',
          subtitle: 'WhatsApp is cheaper and richer. SMS is a fallback.',
        ),
        const SizedBox(height: 4),
        _ChannelTile(
          icon: Icons.chat_bubble,
          iconColor: const Color(0xFF25D366),
          title: 'WhatsApp',
          subtitle: widget.whatsappPrice != null
              ? 'R${widget.whatsappPrice!.toStringAsFixed(2)} per recipient'
              : 'Pricing loading…',
          value: widget.sendWhatsApp,
          onChanged: widget.onWhatsAppChanged,
        ),
        _ChannelTile(
          icon: Icons.sms,
          iconColor: Colors.blueGrey,
          title: 'SMS',
          subtitle: widget.smsPricePerSegment != null
              ? 'R${widget.smsPricePerSegment!.toStringAsFixed(2)} per segment ($smsSegments segment${smsSegments == 1 ? '' : 's'})'
              : 'Pricing loading…',
          value: widget.sendSMS,
          onChanged: widget.onSMSChanged,
        ),
        if (noChannelsChosen)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Pick at least one channel to continue.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),

        // ── Section: Preview ─────────────────────────────────────────────
        if (selected != null && waContent.isNotEmpty) ...[
          SizedBox(height: SizeConfig.heightMultiplier * 3),
          _SectionHeader(
            title: 'Preview',
            subtitle:
                'How your message will look to a customer named "[Customer Name]".',
          ),
          const SizedBox(height: 8),
          if (widget.sendWhatsApp && widget.sendSMS)
            _PreviewToggle(
              channel: _previewChannel,
              onChanged: (c) => setState(() => _previewChannel = c),
            ),
          const SizedBox(height: 4),
          MessagePreviewCard(
            content: _renderPreview(
              _previewChannel == _PreviewChannel.whatsapp
                  ? waContent
                  : smsContent,
            ),
            mediaUrl:
                _previewChannel == _PreviewChannel.whatsapp ? mediaUrl : null,
          ),
          if (widget.sendWhatsApp &&
              widget.sendSMS &&
              smsContent == waContent)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                'SMS uses the same content as WhatsApp for this template.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.disabledColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
        SizedBox(height: SizeConfig.heightMultiplier * 4),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.disabledColor),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ChannelTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: value
              ? theme.colorScheme.primary.withOpacity(0.4)
              : theme.dividerColor.withOpacity(0.4),
        ),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        secondary: Icon(icon, color: iconColor),
        title: Text(title,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      ),
    );
  }
}

class _PreviewToggle extends StatelessWidget {
  final _PreviewChannel channel;
  final ValueChanged<_PreviewChannel> onChanged;

  const _PreviewToggle({required this.channel, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_PreviewChannel>(
      segments: const [
        ButtonSegment(
          value: _PreviewChannel.whatsapp,
          label: Text('WhatsApp'),
          icon: Icon(Icons.chat_bubble, size: 16),
        ),
        ButtonSegment(
          value: _PreviewChannel.sms,
          label: Text('SMS'),
          icon: Icon(Icons.sms, size: 16),
        ),
      ],
      selected: {channel},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const _InlineNotice({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color.withOpacity(0.9), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTemplatesState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyTemplatesState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.2),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.library_books_outlined,
              size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            'No templates yet',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Templates are pre-approved messages you can send to your customers. WhatsApp needs to approve each one before it can be used.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.disabledColor),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Create your first template'),
          ),
        ],
      ),
    );
  }
}
