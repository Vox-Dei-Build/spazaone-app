import 'package:flutter/material.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';

class FlashHelloPaisaDetailsWidget extends StatelessWidget {
  final TextEditingController vendorIdController;
  final TextEditingController referenceNumberController;
  final String selectedService;
  final List<String> banks;
  final String? selectedBank;
  final Function(String?) onBankChanged;
  final Map<String, String> accountDetails;

  const FlashHelloPaisaDetailsWidget({
    Key? key,
    required this.vendorIdController,
    required this.referenceNumberController,
    required this.selectedService,
    required this.banks,
    required this.selectedBank,
    required this.onBankChanged,
    required this.accountDetails,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: selectedBank,
          onChanged: onBankChanged,
          items: banks.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          decoration: InputDecoration(
            labelText: 'Bank',
            prefixIcon: Icon(Icons.account_balance),
          ),
        ),
        CustomTextField(
          hintText: 'Account Name',
          prefixIcon: Icons.account_box,
          label: 'Account Name',
          controller: TextEditingController(
              text:
                  accountDetails['AccountName']), // Prepopulated and read-only
          readOnly: true,
        ),
        CustomTextField(
          label: 'Account Number',
          hintText: 'Account Number',
          controller: TextEditingController(
              text: accountDetails[selectedBank]), // Prepopulated and read-only
          readOnly: true,
          prefixIcon: Icons.numbers,
        ),
        CustomTextField(
          label: selectedService == 'Flash'
              ? 'Flash Number (Vendor ID)'
              : 'HelloPaisa Reference Number',
          hintText: selectedService == 'Flash'
              ? 'Enter your Flash Number'
              : 'Enter your 14-digit HelloPaisa Reference Number',
          prefixIcon: Icons.confirmation_num,
          controller: selectedService == 'Flash'
              ? vendorIdController
              : referenceNumberController,
          validator: (value) {
            if (value!.isEmpty ||
                (selectedService == 'HelloPaisa' && value.length != 14)) {
              return 'Please enter a valid ${selectedService == 'Flash' ? 'Flash Number' : '14-digit HelloPaisa Reference Number'}';
            }
            return null;
          },
        ),
      ],
    );
  }
}
