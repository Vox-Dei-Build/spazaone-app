import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/ledger/widgets/entity_tab.dart';
import 'package:pasella/pages/ledger/widgets/customer_search_box.dart';

class CustomerTab extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: SizeConfig.heightMultiplier * 1),
        ValueListenableBuilder<bool>(
          valueListenable: hasCustomersNotifier,
          builder: (context, hasCustomers, child) {
            return hasCustomers
                ? CustomerSearchBox(searchTextNotifier: searchTextNotifier)
                : const SizedBox.shrink();
          },
        ),
        Expanded(
          child: EntityTab(
            searchTextNotifier: searchTextNotifier,
            category: "Customer",
            emptyAsset: 'assets/images/customer.png',
            emptyText:
                'Add your first customer so you can record a sale and send a WhatsApp confirmation.',
            hasCustomersNotifier: hasCustomersNotifier,
            emptyCtaLabel:
                onAddCustomer == null ? null : 'Add your first customer',
            onEmptyCtaTap: onAddCustomer,
          ),
        ),
      ],
    );
  }
}
