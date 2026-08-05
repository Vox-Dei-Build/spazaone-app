import 'package:flutter/material.dart';

/// A primary page tab bar with one page-local utility action.
///
/// At large accessibility text sizes the tabs become scrollable rather than
/// fading or truncating to make room for the fixed 48dp utility action.
class ContextualTabBar extends StatelessWidget {
  const ContextualTabBar({
    super.key,
    required this.tabs,
    required this.action,
    this.controller,
    this.labelStyle,
    this.unselectedLabelStyle,
    this.labelPadding,
  });

  final List<Widget> tabs;
  final Widget action;
  final TabController? controller;
  final TextStyle? labelStyle;
  final TextStyle? unselectedLabelStyle;
  final EdgeInsetsGeometry? labelPadding;

  @override
  Widget build(BuildContext context) {
    final fontSize = labelStyle?.fontSize ?? 14;
    final useScrollableTabs =
        MediaQuery.textScalerOf(context).scale(fontSize) >= 20;

    return Row(
      children: [
        Expanded(
          child: TabBar(
            controller: controller,
            isScrollable: useScrollableTabs,
            tabAlignment: useScrollableTabs ? TabAlignment.start : null,
            labelPadding: useScrollableTabs
                ? const EdgeInsets.symmetric(horizontal: 12)
                : labelPadding,
            labelStyle: labelStyle,
            unselectedLabelStyle: unselectedLabelStyle,
            tabs: tabs,
          ),
        ),
        action,
      ],
    );
  }
}
