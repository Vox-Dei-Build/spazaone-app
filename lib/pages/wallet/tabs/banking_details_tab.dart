import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';

class BankingDetailsTab extends StatefulWidget {
  const BankingDetailsTab({super.key});

  @override
  State<BankingDetailsTab> createState() => _BankingDetailsTabState();
}

class _BankingDetailsTabState extends State<BankingDetailsTab> {
  final WalletViewModel walletViewModel = WalletViewModel();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController accountHolderController = TextEditingController();
  final TextEditingController accountNumberController = TextEditingController();

  // Defined Account Types List
  final List<String> accountTypes = ['Savings', 'Current', 'Business'];
  String? selectedAccountType; // Allow null initially

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBankingDetails();
  }

  @override
  void dispose() {
    walletViewModel.dispose();
    super.dispose();
  }

  // 🟢 Corrected Banking Details Loader
  Future<void> _loadBankingDetails() async {
    setState(() => isLoading = true);
    await walletViewModel.initializeBankingDetails();

    if (walletViewModel.editingDocumentId != null) {
      final details = await walletViewModel
          .fetchBankingDetails(walletViewModel.editingDocumentId!);
      if (details != null) {
        setState(() {
          walletViewModel.accountHolderName.text = details.accountHolderName;
          walletViewModel.accountNumber.text = details.accountNumber;

          // Validate selected account type
          if (accountTypes.contains(details.selectedAccountType)) {
            selectedAccountType = details.selectedAccountType;
          } else {
            selectedAccountType = accountTypes.first; // Default fallback
          }
        });
      } else {
        setState(() {
          selectedAccountType = accountTypes.first; // Ensure default
        });
      }
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: SizeConfig.imageSizeMultiplier * 4),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    DropdownButtonFormField<String>(
                      value: selectedAccountType,
                      items: accountTypes
                          .map((type) => DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() => selectedAccountType = value!);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Account Type',
                        prefixIcon: Icon(Icons.account_balance_wallet),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: walletViewModel.accountHolderName,
                      decoration: const InputDecoration(
                        labelText: 'Account Holder Name',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Enter account holder name'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: walletViewModel.accountNumber,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Account Number',
                        prefixIcon: Icon(Icons.account_balance_wallet),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Enter valid account number'
                          : null,
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          await walletViewModel.saveBankingDetails(
                            context,
                            'Bank', // Defaulting to "Bank" as a service type
                            selectedAccountType!,
                          );
                        }
                      },
                      child: const Text('Save Banking Details'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
