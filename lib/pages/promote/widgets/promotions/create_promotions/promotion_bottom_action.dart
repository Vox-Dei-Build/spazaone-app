import 'package:flutter/material.dart';

/// Persistent action surface for promotion wizards.
///
/// Use this as [Scaffold.bottomNavigationBar]. The scaffold keeps it above the
/// keyboard while [SafeArea] protects it from Android gesture/navigation bars
/// and the iPhone home indicator.
class PromotionBottomAction extends StatelessWidget {
  const PromotionBottomAction({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: child,
        ),
      ),
    );
  }
}
