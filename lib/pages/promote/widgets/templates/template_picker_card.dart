import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/promote/utils/template_status.dart';

/// Selectable card representing a single messaging template.
///
/// Shows the template name, a 2-line body snippet, channel badges (WA / SMS)
/// and an approval status pill. Approved templates are tappable; pending /
/// rejected / submission-failed render disabled with a muted appearance.
class TemplatePickerCard extends StatelessWidget {
  final Map<String, dynamic> template;
  final bool selected;
  final VoidCallback? onTap;

  const TemplatePickerCard({
    super.key,
    required this.template,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = templateStatusOf(template);
    final disabled = !status.isUsable;
    final name =
        (template['displayName'] ?? template['name'] ?? 'Untitled').toString();
    final whatsappContent =
        (template['channels']?['whatsapp']?['templateContent'] ?? '')
            .toString();
    final hasWhatsApp = template['channels']?['whatsapp'] != null;
    final hasSms = template['channels']?['sms'] != null;
    final mediaUrl = template['channels']?['whatsapp']?['mediaUrl'] as String?;

    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.dividerColor.withOpacity(0.4);

    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpazaRadius.surface),
          side: BorderSide(color: borderColor, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(SpazaRadius.surface),
          onTap: disabled ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.disabledColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          _StatusPill(status: status),
                        ],
                      ),
                      if (whatsappContent.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          whatsappContent,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.75),
                            height: 1.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (hasWhatsApp)
                            const _ChannelBadge(
                              icon: Icons.chat_bubble,
                              label: 'WhatsApp',
                              color: Color(0xFF25D366),
                            ),
                          if (hasSms)
                            const _ChannelBadge(
                              icon: Icons.sms,
                              label: 'SMS',
                              color: Colors.blueGrey,
                            ),
                          if (mediaUrl != null && mediaUrl.isNotEmpty) ...[
                            const _ChannelBadge(
                              icon: Icons.image_outlined,
                              label: 'Image',
                              color: Colors.deepPurple,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
        border: Border.all(color: status.color.withOpacity(0.5), width: 1),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChannelBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ChannelBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
