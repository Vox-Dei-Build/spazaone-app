import 'package:flutter/material.dart';

class ActionsDock extends StatelessWidget {
  const ActionsDock({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    // Cap the dock between 120 and ~1/3 of screen height
    final maxH = h * 0.33;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 0,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // Minimum height so one/two buttons look good,
            // maximum height so it never takes over the screen.
            minHeight: 72,
            maxHeight: maxH.clamp(120.0, 280.0),
          ),
          child: SingleChildScrollView(
            // If there are many buttons, the area scrolls
            physics: const ClampingScrollPhysics(),
            child: child,
          ),
        ),
      ),
    );
  }
}
