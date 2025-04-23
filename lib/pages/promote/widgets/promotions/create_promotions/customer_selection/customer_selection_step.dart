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

  const CustomerSelectionStep({
    Key? key,
    required this.allCustomers,
    required this.customers,
    required this.selectedCustomerIds,
    required this.onAllCustomersChanged,
    required this.onCustomerToggle,
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
