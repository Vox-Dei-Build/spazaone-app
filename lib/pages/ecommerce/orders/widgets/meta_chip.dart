import 'package:flutter/material.dart';

class MetaChip extends StatelessWidget {
  const MetaChip({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final max = MediaQuery.of(context).size.width * 0.55;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: max),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Flexible(
                child:
                    Text(label, style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}
