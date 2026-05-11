import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/utils/currency_util.dart';

class CustomerSelectionStep extends StatelessWidget {
  final bool allCustomers;
  final List<Map<String, dynamic>> customers;
  final Set<String> selectedCustomerIds;
  final ValueChanged<bool> onAllCustomersChanged;
  final ValueChanged<String> onCustomerToggle;

  /// Number of customers filtered out of [customers] because they have
  /// no phone number. Shown as an inline notice so the merchant
  /// understands why their customer count here can be smaller than on
  /// the Ledger page.
  final int hiddenWithoutNumberCount;

  const CustomerSelectionStep({
    Key? key,
    required this.allCustomers,
    required this.customers,
    required this.selectedCustomerIds,
    required this.onAllCustomersChanged,
    required this.onCustomerToggle,
    this.hiddenWithoutNumberCount = 0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text("👥 Select Customers",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: SizeConfig.textMultiplier * 2)),
        if (hiddenWithoutNumberCount > 0)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 2,
              vertical: SizeConfig.heightMultiplier * 0.5,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hiddenWithoutNumberCount == 1
                          ? '1 customer is hidden because they have no phone number.'
                          : '$hiddenWithoutNumberCount customers are hidden because they have no phone number.',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            value: allCustomers,
            onChanged: (_) => onAllCustomersChanged(!allCustomers),
            title: Text("All Customers",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: SizeConfig.textMultiplier * 2))),
        Expanded(
          child: ListView.builder(
            itemCount: customers.length,
            itemBuilder: (context, index) {
              final customer = customers[index];
              final name = customer['name'] ?? '';
              final number = customer['number'] ?? '';
              final balance = customer['balance']?.toDouble() ?? 0.0;
              final id = customer['id'];
              final profileImageUrl = customer['profileImageUrl'];

              final isSelected = selectedCustomerIds.contains(id);

              return CheckboxListTile(
                value: allCustomers ? true : isSelected,
                onChanged: allCustomers
                    ? null // disable taps when “All” is on
                    : (_) => onCustomerToggle(id),
                title: Row(
                  children: [
                    profilePicture(
                        context, name, profileImageUrl, number, true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                            fontSize: SizeConfig.textMultiplier * 1.8,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      CurrencyUtil.format(balance),
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.6,
                        color: balance >= 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        ),
      ],
    );
  }
}
