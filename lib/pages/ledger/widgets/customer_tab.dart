import 'package:flutter/material.dart';
import 'package:pasella/pages/ledger/widgets/entity_tab.dart';
import 'package:pasella/pages/ledger/widgets/customer_search_box.dart';

class CustomerTab extends StatelessWidget {
  final ValueNotifier<String?> searchTextNotifier;
  final ValueNotifier<bool> hasCustomersNotifier;

  CustomerTab({
    required this.searchTextNotifier,
    required this.hasCustomersNotifier,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10.0),
        ValueListenableBuilder<bool>(
          valueListenable: hasCustomersNotifier,
          builder: (context, hasCustomers, child) {
            return hasCustomers
                ? CustomerSearchBox(searchTextNotifier: searchTextNotifier)
                : SizedBox.shrink();
          },
        ),
        Expanded(
          child: EntityTab(
            searchTextNotifier: searchTextNotifier,
            category: "Customer",
            emptyAsset: 'assets/images/customer.png',
            emptyText:
                'Add all your customers here and save time by easily recording sale/purchase done with them.',
            hasCustomersNotifier: hasCustomersNotifier,
          ),
        ),
      ],
    );
  }
}
