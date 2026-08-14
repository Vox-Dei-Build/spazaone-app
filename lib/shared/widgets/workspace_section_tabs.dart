import 'package:flutter/material.dart';

@immutable
class WorkspaceSectionTab {
  const WorkspaceSectionTab({
    required this.label,
    required this.semanticLabel,
  });

  final String label;
  final String semanticLabel;
}

/// Quiet, visible navigation for the small number of jobs within a workspace.
///
/// The visual treatment deliberately matches the focused Wallet & payments
/// screens: neutral labels, one green underline, and no filled selected tile.
/// These destinations change the purpose of the whole page, so they remain
/// visible instead of being hidden in a filter or popup menu. Labels may use
/// two lines at large text sizes while every destination keeps equal width.
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
    final largeText = MediaQuery.textScalerOf(context).scale(14) >= 19;

    final selectedIndex = resolvedController.index;
    return Container(
      key: const ValueKey('workspace-section-tabs'),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < widget.tabs.length; index++)
            Expanded(
              child: _WorkspaceSectionDestination(
                tab: widget.tabs[index],
                selected: selectedIndex == index,
                height: largeText ? 68 : 48,
                onTap: () {
                  if (selectedIndex == index) return;
                  resolvedController.animateTo(index);
                },
              ),
            ),
        ],
      ),
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
      label: tab.semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('workspace-section-${tab.label}'),
          onTap: onTap,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? colors.primary : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            child: Text(
              tab.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    height: 1.15,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
