import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TimelineRow extends StatelessWidget {
  const TimelineRow({
    super.key,
    this.createdAt,
    this.paidAt,
    this.collectedAt,
    this.whatsAppAt,
    this.whatsAppLabel,
  });

  final DateTime? createdAt;
  final DateTime? paidAt;
  final DateTime? collectedAt;

  /// PAS-AI-02: most-recent WhatsApp event timestamp (sent / delivered / replied).
  final DateTime? whatsAppAt;

  /// Short label describing which WhatsApp event the timestamp represents
  /// (e.g. "Sent", "Delivered", "Replied"). When null, the WA step is hidden.
  final String? whatsAppLabel;

  @override
  Widget build(BuildContext context) {
    final steps = <_TimelineStep>[
      _TimelineStep(label: 'Created', at: createdAt),
      _TimelineStep(label: 'Paid', at: paidAt),
      _TimelineStep(label: 'Collected', at: collectedAt),
      if (whatsAppLabel != null)
        _TimelineStep(label: whatsAppLabel!, at: whatsAppAt),
    ];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 420 && steps.length > 3;
            if (isCompact) {
              final itemWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  for (final step in steps)
                    SizedBox(
                      width: itemWidth,
                      child: _TimelineStepTile(step: step),
                    ),
                ],
              );
            }

            final children = <Widget>[];
            for (var i = 0; i < steps.length; i++) {
              children.add(
                Expanded(
                  child: _TimelineStepTile(step: steps[i]),
                ),
              );
              if (i != steps.length - 1) {
                children.add(
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      child: Divider(
                        indent: 8,
                        endIndent: 8,
                        thickness: 2,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ),
                );
              }
            }

            return Row(children: children);
          },
        ),
      ),
    );
  }
}

class _TimelineStep {
  const _TimelineStep({required this.label, this.at});

  final String label;
  final DateTime? at;

  bool get isActive => at != null;
}

class _TimelineStepTile extends StatelessWidget {
  const _TimelineStepTile({required this.step});

  final _TimelineStep step;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: step.isActive
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade400,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          step.label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (step.at != null)
          Text(
            DateFormat('dd MMM • HH:mm').format(step.at!),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall,
          ),
      ],
    );
  }
}
