import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';

/// Plain page-local context below the visible workspace destinations.
class WorkspaceContextHeader extends StatelessWidget {
  const WorkspaceContextHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: kTertiaryColor,
                fontWeight: FontWeight.w800,
                letterSpacing: -.2,
              ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: kSecondaryAccent,
                height: 1.35,
              ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = action != null &&
              MediaQuery.textScalerOf(context).scale(14) >= 20;
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                text,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: text),
              if (action != null) ...[
                const SizedBox(width: 12),
                action!,
              ],
            ],
          );
        },
      ),
    );
  }
}
