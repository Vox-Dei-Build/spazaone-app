import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/services/payment_setup_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/widgets/private_region.dart';

@visibleForTesting
String? canonicalSettlementAccountType(String value) {
  switch (value.trim().toLowerCase()) {
    case 'personal':
      return 'personal';
    case 'business':
      return 'business';
    default:
      return null;
  }
}

class AddBankingDetailsPage extends StatefulWidget {
  final WalletViewModel walletViewModel;
  final Future<List<SupportedSettlementBank>> Function()? loadSupportedBanks;

  const AddBankingDetailsPage({
    super.key,
    required this.walletViewModel,
    this.loadSupportedBanks,
  });

  @override
  State<AddBankingDetailsPage> createState() => _AddBankingDetailsPageState();
}

class _AddBankingDetailsPageState extends State<AddBankingDetailsPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  static const _accountTypeLabels = <String, String>{
    'personal': 'Personal',
    'business': 'Business',
  };
  List<SupportedSettlementBank> _banks = const [];
  SupportedSettlementBank? _selectedBank;
  String? _selectedAccountType;
  String? _bankLoadError;
  bool _loadingBanks = true;

  @override
  void initState() {
    super.initState();
    _selectedAccountType = canonicalSettlementAccountType(
      widget.walletViewModel.accountType.text,
    );
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    setState(() {
      _loadingBanks = true;
      _bankLoadError = null;
    });
    try {
      final banks = await (widget.loadSupportedBanks ??
          PaymentSetupService.supportedSettlementBanks)();
      if (!mounted) return;
      final savedName = widget.walletViewModel.bankName.text.trim();
      final savedBranchCode = widget.walletViewModel.branchCode.text.trim();
      SupportedSettlementBank? selected;
      for (final bank in banks) {
        if (bank.branchCode == savedBranchCode ||
            bank.name.toLowerCase() == savedName.toLowerCase()) {
          selected = bank;
          break;
        }
      }
      setState(() {
        _banks = banks;
        _selectedBank = selected;
        _loadingBanks = false;
        if (selected != null) {
          widget.walletViewModel.bankName.text = selected.name;
          widget.walletViewModel.branchCode.text = selected.branchCode;
          if (!selected.supportedAccountTypes.contains(_selectedAccountType)) {
            _selectedAccountType = null;
            widget.walletViewModel.accountType.clear();
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingBanks = false;
        _bankLoadError =
            'We could not load the supported banks. Check your connection and try again.';
      });
    }
  }

  void _selectBank(SupportedSettlementBank? bank) {
    setState(() {
      _selectedBank = bank;
      if (bank == null ||
          !bank.supportedAccountTypes.contains(_selectedAccountType)) {
        _selectedAccountType = null;
        widget.walletViewModel.accountType.clear();
      }
    });
    widget.walletViewModel.bankName.text = bank?.name ?? '';
    widget.walletViewModel.branchCode.text = bank?.branchCode ?? '';
  }

  void _selectAccountType(String? accountType) {
    setState(() => _selectedAccountType = accountType);
    widget.walletViewModel.accountType.text =
        _accountTypeLabels[accountType] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Banking Details'),
      body: Padding(
        padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
        child: Form(
          key: _formKey,
          // Whole banking form is sensitive: account holder, account number,
          // branch code. Wrap the ListView so every field + the live values
          // are masked in replay; AppBar stays visible.
          child: PrivateRegion(
            child: ListView(
              children: [
                DropdownButtonFormField<SupportedSettlementBank>(
                  key: const ValueKey('supported-settlement-bank'),
                  value: _selectedBank,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Bank',
                    helperText: _loadingBanks
                        ? 'Loading banks supported for online payouts…'
                        : 'Only banks currently supported for verification are shown.',
                    prefixIcon: const Icon(Icons.account_balance),
                  ),
                  items: _banks
                      .map(
                        (bank) => DropdownMenuItem(
                          value: bank,
                          child: Text(
                            bank.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _loadingBanks || _bankLoadError != null
                      ? null
                      : _selectBank,
                  validator: (value) =>
                      value == null ? 'Choose a supported bank.' : null,
                ),
                if (_loadingBanks) const LinearProgressIndicator(),
                if (_bankLoadError case final message?)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(child: Text(message)),
                          TextButton(
                            onPressed: _loadBanks,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                CustomTextField(
                  label: 'Account Holder Name',
                  hintText: 'Enter account holder name',
                  prefixIcon: Icons.person,
                  controller: widget.walletViewModel.accountHolderName,
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? 'Enter the account holder name.'
                      : null,
                ),
                CustomTextField(
                  label: 'Account Number',
                  hintText: 'Enter account number',
                  prefixIcon: Icons.account_balance_wallet,
                  controller: widget.walletViewModel.accountNumber,
                  textInputType: TextInputType.number,
                  inputFormat: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 20,
                  validator: (value) =>
                      !RegExp(r'^\d{5,20}$').hasMatch(value?.trim() ?? '')
                          ? 'Enter a valid account number.'
                          : null,
                ),
                DropdownButtonFormField<String>(
                  key: const ValueKey('settlement-bank-account-type'),
                  value: _selectedAccountType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Account type',
                    helperText: 'Choose the type registered with your bank.',
                    prefixIcon: Icon(Icons.merge_type_rounded),
                  ),
                  items: (_selectedBank?.supportedAccountTypes ?? const [])
                      .map(
                        (accountType) => DropdownMenuItem(
                          value: accountType,
                          child: Text(
                            _accountTypeLabels[accountType] ?? accountType,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _selectedBank == null ? null : _selectAccountType,
                  validator: (value) =>
                      value == null ? 'Choose the account type.' : null,
                ),
                CustomTextField(
                  label: 'Universal branch code',
                  hintText: 'Filled in when you choose a bank',
                  prefixIcon: Icons.numbers,
                  controller: widget.walletViewModel.branchCode,
                  textInputType: TextInputType.number,
                  readOnly: true,
                  validator: (value) =>
                      !RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
                          ? 'Choose a supported bank.'
                          : null,
                ),
                CustomTextField(
                  label: 'Reference',
                  hintText: 'Enter reference (optional)',
                  prefixIcon: Icons.notes,
                  controller: widget.walletViewModel.reference,
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 3),
                ValueListenableBuilder<bool>(
                  valueListenable: widget.walletViewModel.isProcessing,
                  builder: (context, isProcessing, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomButton(
                          title: 'Save Banking Details',
                          onTap: () async {
                            if (_formKey.currentState!.validate()) {
                              try {
                                await widget.walletViewModel
                                    .saveBankingDetails();
                                if (!context.mounted) return;
                                showSnackbar(context, 'Banking details saved ✅',
                                    Colors.green);
                                Navigator.pop(context);
                              } catch (e) {
                                if (!context.mounted) return;
                                showSnackbar(
                                    context,
                                    'Something went wrong. Try again.',
                                    Colors.red);
                              }
                            }
                          },
                          color: Colors.green,
                          icon: Icons.check,
                          fontSize: SizeConfig.textMultiplier * 2,
                          width: double.infinity,
                        ),
                        if (widget.walletViewModel.isProcessing.value)
                          const CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
