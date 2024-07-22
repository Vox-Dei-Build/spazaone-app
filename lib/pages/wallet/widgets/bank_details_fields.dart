import 'package:flutter/material.dart';
import 'package:pasella/models/wallet/wallet_model.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';

class BankDetailsWidget extends StatelessWidget {
  final TextEditingController accountHolderNameController;
  final TextEditingController accountNumberController;
  final String selectedAccountType;
  final Function(String?) onAccountTypeChanged;

  const BankDetailsWidget({
    Key? key,
    required this.accountHolderNameController,
    required this.accountNumberController,
    required this.selectedAccountType,
    required this.onAccountTypeChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: selectedAccountType,
          onChanged: onAccountTypeChanged,
          items: accountTypes.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          decoration: InputDecoration(
            labelText: 'Account Type',
            prefixIcon: Icon(Icons.account_balance_wallet),
          ),
        ),
        CustomTextField(
          hintText: 'Account Holder Name',
          prefixIcon: Icons.person,
          label: 'Account Holder Name',
          controller: accountHolderNameController,
          validator: (value) =>
              value!.isEmpty ? 'Please enter account holder name' : null,
        ),
        CustomTextField(
          label: 'Account Number',
          hintText: 'Account Number',
          controller: accountNumberController,
          prefixIcon: Icons.numbers,
          validator: (value) =>
              value!.isEmpty ? 'Please enter a valid account number' : null,
        ),
      ],
    );
  }
}
