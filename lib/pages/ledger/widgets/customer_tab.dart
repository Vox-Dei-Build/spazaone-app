import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pasella/pages/ledger/widgets/customer_search_box.dart';
import 'package:pasella/pages/ledger/widgets/entity_tab.dart';
import 'package:pasella/shared/widgets/workspace_context_header.dart';

class CustomerTab extends StatefulWidget {
  final ValueNotifier<String?> searchTextNotifier;
  final ValueNotifier<bool> hasCustomersNotifier;

  /// PAS-UX-09: optional tap handler for the empty-state CTA. When
  /// supplied, the empty Customers tab renders a primary "Add your
  /// first customer" button beneath the placeholder so the hero loop
  /// has an obvious entry point that doesn't depend on noticing the
  /// floating "+" FAB.
  final VoidCallback? onAddCustomer;

  const CustomerTab({
    required this.searchTextNotifier,
    required this.hasCustomersNotifier,
    this.onAddCustomer,
    Key? key,
  }) : super(key: key);

  @override
  State<CustomerTab> createState() => _CustomerTabState();
}

class _CustomerTabState extends State<CustomerTab> {
  // PAS-UX: shared scroll controller passed into the customer list so
  // we can react to scroll direction and hide the search bar when the
  // merchant is browsing down a long list (reclaiming ~5% of vertical
  // space) and re-show it the moment they scroll up to look for a new
  // term.
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _searchVisible = ValueNotifier<bool>(true);
  final FocusNode _searchFocusNode = FocusNode();

  // Small delta threshold so finger jitter doesn't toggle visibility
  // back and forth — only deliberate scroll gestures should collapse
  // the bar.
  static const double _scrollDelta = 8.0;
  double _lastOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _searchFocusNode.addListener(_handleFocusChange);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final offset = position.pixels;

    // Always show the bar when the list is at (or above) the top —
    // this guarantees the bar returns to view on tab switch / pull
    // to refresh / quick scroll-to-top.
    if (offset <= 0) {
      if (!_searchVisible.value) _searchVisible.value = true;
      _lastOffset = offset;
      return;
    }

    // Never collapse while the input is focused: typing while the bar
    // is animating away would be jarring and could dismiss the
    // keyboard unexpectedly.
    if (_searchFocusNode.hasFocus) {
      _lastOffset = offset;
      return;
    }

    final delta = offset - _lastOffset;
    if (delta.abs() < _scrollDelta) return;

    final direction = position.userScrollDirection;
    if (direction == ScrollDirection.reverse && _searchVisible.value) {
      _searchVisible.value = false;
    } else if (direction == ScrollDirection.forward && !_searchVisible.value) {
      _searchVisible.value = true;
    }
    _lastOffset = offset;
  }

  void _handleFocusChange() {
    // Focusing the field should always reveal it (covers the edge
    // case where some other UI element programmatically focuses the
    // input while the bar is collapsed).
    if (_searchFocusNode.hasFocus && !_searchVisible.value) {
      _searchVisible.value = true;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _searchFocusNode.removeListener(_handleFocusChange);
    _searchFocusNode.dispose();
    _searchVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: widget.hasCustomersNotifier,
          builder: (context, hasCustomers, child) {
            return Column(
              children: [
                WorkspaceContextHeader(
                  title: 'Your customers',
                  subtitle: 'People who buy from your shop',
                  action: hasCustomers && widget.onAddCustomer != null
                      ? FilledButton.icon(
                          onPressed: widget.onAddCustomer,
                          icon: const Icon(Icons.add_rounded, size: 19),
                          label: const Text('Add'),
                        )
                      : null,
                ),
                if (hasCustomers)
                  // The search field remains sticky while browsing a long
                  // customer list, but the page purpose stays visible above.
                  ValueListenableBuilder<bool>(
                    valueListenable: _searchVisible,
                    builder: (context, visible, _) {
                      return AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: visible ? 1.0 : 0.0,
                          child: visible
                              ? CustomerSearchBox(
                                  searchTextNotifier: widget.searchTextNotifier,
                                  focusNode: _searchFocusNode,
                                )
                              : const SizedBox(
                                  width: double.infinity,
                                  height: 0,
                                ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
        Expanded(
          child: EntityTab(
            searchTextNotifier: widget.searchTextNotifier,
            scrollController: _scrollController,
            category: "Customer",
            emptyAsset: 'assets/images/customer.webp',
            emptyText: 'No customers yet',
            hasCustomersNotifier: widget.hasCustomersNotifier,
            emptyCtaLabel: widget.onAddCustomer == null ? null : 'Add customer',
            onEmptyCtaTap: widget.onAddCustomer,
          ),
        ),
      ],
    );
  }
}
