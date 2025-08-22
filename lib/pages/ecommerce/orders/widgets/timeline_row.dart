import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TimelineRow extends StatelessWidget {
  const TimelineRow({super.key, this.createdAt, this.paidAt, this.collectedAt});
  final DateTime? createdAt;
  final DateTime? paidAt;
  final DateTime? collectedAt;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget dot(bool active) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade400,
            shape: BoxShape.circle,
          ),
        );
    Widget label(String text, DateTime? dt, bool active) => Column(
          children: [
            Text(text,
                style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            if (dt != null)
              Text(DateFormat('dd MMM • HH:mm').format(dt), style: t.bodySmall),
          ],
        );
    final createdActive = createdAt != null;
    final paidActive = paidAt != null;
    final collectedActive = collectedAt != null;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(children: [
              dot(createdActive),
              const SizedBox(height: 6),
              label('Created', createdAt, createdActive)
            ]),
            const Expanded(
                child: Divider(indent: 8, endIndent: 8, thickness: 2)),
            Column(children: [
              dot(paidActive),
              const SizedBox(height: 6),
              label('Paid', paidAt, paidActive)
            ]),
            const Expanded(
                child: Divider(indent: 8, endIndent: 8, thickness: 2)),
            Column(children: [
              dot(collectedActive),
              const SizedBox(height: 6),
              label('Collected', collectedAt, collectedActive)
            ]),
          ],
        ),
      ),
    );
  }
}
