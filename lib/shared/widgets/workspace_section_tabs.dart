import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/shared/widgets/responsive_app_layout.dart';

@immutable
class WorkspaceSectionTab {
  const WorkspaceSectionTab({
    required this.label,
    required this.semanticLabel,
    this.badgeCount = 0,
  });

  final String label;
  final String semanticLabel;
  final int badgeCount;
}

/// Visible navigation for the small number of jobs within a workspace.
///
/// These destinations change the purpose of the whole page, so they remain
/// visible instead of being hidden in a filter or popup menu. A white selected
/// surface sits within one soft group, matching the approachable app theme.
class WorkspaceSectionTabs extends StatefulWidget {
  const WorkspaceSectionTabs({
    super.key,
    required this.tabs,
    this.controller,
    this.onSelected,
  });

  final List<WorkspaceSectionTab> tabs;
  final TabController? controller;
  final ValueChanged<int>? onSelected;

  @override
  State<WorkspaceSectionTabs> createState() => _WorkspaceSectionTabsState();
}

class _WorkspaceSectionTabsState extends State<WorkspaceSectionTabs> {
  TabController? _controller;
  int? _lastIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindController();
  }

  @override
  void didUpdateWidget(covariant WorkspaceSectionTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _bindController();
  }

  void _bindController() {
    final next = widget.controller ?? DefaultTabController.of(context);
    if (identical(_controller, next)) return;
    _controller?.removeListener(_handleControllerChanged);
    _controller = next;
    _lastIndex = next.index;
    next.addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    final index = _controller?.index;
    if (!mounted || index == null || index == _lastIndex) return;
    _lastIndex = index;
    widget.onSelected?.call(index);
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.tabs.length >= 2);
    final resolvedController = _controller!;
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) >= 20;
    final compactLandscape = usesCompactLandscapeLayout(context) && !largeText;

    final selectedIndex = resolvedController.index;
    final hasBadges = widget.tabs.any((tab) => tab.badgeCount > 0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const ValueKey('workspace-section-tabs'),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(SpazaRadius.control),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var index = 0; index < widget.tabs.length; index++)
                Expanded(
                  child: _WorkspaceSectionDestination(
                    tab: widget.tabs[index],
                    selected: selectedIndex == index,
                    height: largeText
                        ? MediaQuery.textScalerOf(context).scale(14) * 2.2 +
                            16 +
                            (hasBadges
                                ? MediaQuery.textScalerOf(context).scale(11) + 8
                                : 0)
                        : (compactLandscape ? 38 : 44),
                    onTap: () {
                      if (selectedIndex == index) return;
                      resolvedController.animateTo(index);
                    },
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          key: const ValueKey('workspace-section-boundary'),
          height: compactLandscape ? 4 : 12,
        ),
      ],
    );
  }
}

class _WorkspaceSectionDestination extends StatelessWidget {
  const _WorkspaceSectionDestination({
    required this.tab,
    required this.selected,
    required this.height,
    required this.onTap,
  });

  final WorkspaceSectionTab tab;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.badgeCount > 0
          ? '${tab.semanticLabel}, ${tab.badgeCount} unread'
          : tab.semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('workspace-section-${tab.label}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _label(context, colors),
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, ColorScheme colors) {
    final largeText = MediaQuery.textScalerOf(context).scale(14) >= 20;
    final label = Text(
      tab.label,
      maxLines: largeText ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? kTertiaryColor : colors.onSurfaceVariant,
            fontWeight: FontWeight.w500,
            height: 1.1,
          ),
    );
    if (tab.badgeCount <= 0) return label;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tab.badgeCount > 99 ? '99+' : '${tab.badgeCount}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onSecondaryContainer,
              height: 1,
            ),
      ),
    );
    if (largeText) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        label,
        const SizedBox(height: 4),
        badge,
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: label),
      const SizedBox(width: 4),
      badge,
    ]);
  }
}
