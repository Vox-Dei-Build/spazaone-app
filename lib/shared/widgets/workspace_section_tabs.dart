import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';

@immutable
class WorkspaceSectionTab {
  const WorkspaceSectionTab({
    required this.label,
    required this.semanticLabel,
  });

  final String label;
  final String semanticLabel;
}

/// Visible navigation for the small number of jobs within a workspace.
///
/// These destinations change the purpose of the whole page, so they remain
/// visible instead of being hidden in a filter or popup menu. The rounded
/// surface deliberately avoids ruled navigation lines, which become visually
/// heavy on a small phone.
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

    final selectedIndex = resolvedController.index;
    return Container(
      key: const ValueKey('workspace-section-tabs'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < widget.tabs.length; index++)
            Expanded(
              child: _WorkspaceSectionDestination(
                tab: widget.tabs[index],
                selected: selectedIndex == index,
                height: largeText ? 62 : 44,
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
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Section tabs are navigation, not calls to action. Keep the
              // brand green available for actions such as Add, Record sale,
              // and Add money; navy gives selected destinations a clear but
              // quieter hierarchy.
              color: selected ? kTertiaryColor : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              tab.label,
              maxLines:
                  MediaQuery.textScalerOf(context).scale(14) >= 20 ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? Colors.white : colors.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    height: 1.1,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
