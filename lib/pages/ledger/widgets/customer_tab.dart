import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/sales/sales_intent_bus.dart';
import 'package:pasella/pages/settings/share/share.dart';
import 'package:pasella/pages/ledger/widgets/entity_tab.dart';
import 'package:pasella/pages/ledger/widgets/customer_search_box.dart';
import 'package:pasella/pages/wallet/tabs/info_center_tab.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/shared/widgets/onboarding/customer_onboarding_checklist_card.dart';
import 'package:provider/provider.dart';

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
        SizedBox(height: SizeConfig.heightMultiplier * 1),
        ValueListenableBuilder<bool>(
          valueListenable: widget.hasCustomersNotifier,
          builder: (context, hasCustomers, child) {
            if (!hasCustomers) return const SizedBox.shrink();
            // PAS-UX: sticky-on-scroll. The bar collapses to zero
            // height (with a fade) when scrolling down and reappears
            // on scroll-up. AnimatedSize handles the layout shrink so
            // the list below smoothly takes the reclaimed space.
            return ValueListenableBuilder<bool>(
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
                        : const SizedBox(width: double.infinity, height: 0),
                  ),
                );
              },
            );
          },
        ),
        Expanded(
          child: EntityTab(
            searchTextNotifier: widget.searchTextNotifier,
            scrollController: _scrollController,
            category: "Customer",
            emptyAsset: 'assets/images/customer.png',
            emptyText:
                'Add your first customer so you can record a sale and send a WhatsApp confirmation.',
            hasCustomersNotifier: widget.hasCustomersNotifier,
            emptyCtaLabel:
                widget.onAddCustomer == null ? null : 'Add your first customer',
            onEmptyCtaTap: widget.onAddCustomer,
            listHeader: CustomerOnboardingChecklistCard(
              userId: FirebaseAuth.instance.currentUser?.uid ?? '',
              onAddCustomer: widget.onAddCustomer ?? () {},
              onChooseWhatsAppProduct: () => _openProducts(context),
              onOpenOrderingLink: () => _openOrderingLink(context),
              onOpenPromotions: () => _openPromotions(context),
              onOpenBanking: () => _openBanking(context),
            ),
            // PAS-AUTH-03: bring Customers up to Stock-parity by
            // surfacing the existing TUTORIAL_CAPTURE_CUSTOMERS Loom
            // video on the empty state. The remote-config key already
            // existed; it just wasn't wired into the surface that needs
            // it most.
            tutorialKey: TutorialConfig.TUTORIAL_CAPTURE_CUSTOMERS,
            tutorialTitle: 'How to add and message customers',
          ),
        ),
      ],
    );
  }

  void _openProducts(BuildContext context) {
    context.read<AppModel>().updateCurrentIndex(1);
  }

  void _openOrderingLink(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SharePage(source: 'customer_onboarding'),
      ),
    );
  }

  void _openPromotions(BuildContext context) {
    SalesIntentBus.instance.set(
      const SalesIntent(
        section: SalesIntentSection.marketing,
        marketingView: SalesIntentMarketingView.promotions,
      ),
    );
    context.read<AppModel>().updateCurrentIndex(2);
  }

  void _openBanking(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WalletPage(
          initialTab: WalletInitialTab.account,
          initialAccountView: InfoView.banking,
        ),
      ),
    );
  }
}
