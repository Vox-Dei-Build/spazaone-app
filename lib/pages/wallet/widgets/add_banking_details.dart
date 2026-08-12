import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/widgets/private_region.dart';

class AddBankingDetailsPage extends StatefulWidget {
  final WalletViewModel walletViewModel;
  const AddBankingDetailsPage({super.key, required this.walletViewModel});

  @override
  State<AddBankingDetailsPage> createState() => _AddBankingDetailsPageState();
}

class _AddBankingDetailsPageState extends State<AddBankingDetailsPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

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
                CustomTextField(
                  label: 'Bank Name',
                  hintText: 'Enter bank name',
                  prefixIcon: Icons.account_balance,
                  controller: widget.walletViewModel.bankName,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Bank name required'
                      : null,
                ),
                CustomTextField(
                  label: 'Account Holder Name',
                  hintText: 'Enter account holder name',
                  prefixIcon: Icons.person,
                  controller: widget.walletViewModel.accountHolderName,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Account holder name required'
                      : null,
                ),
                CustomTextField(
                  label: 'Account Number',
                  hintText: 'Enter account number',
                  prefixIcon: Icons.account_balance_wallet,
                  controller: widget.walletViewModel.accountNumber,
                  textInputType: TextInputType.number,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Account number required'
                      : null,
                ),
                CustomTextField(
                  label: 'Account Type',
                  hintText: 'E.g., Savings, Current, Business',
                  prefixIcon: Icons.merge_type_rounded,
                  controller: widget.walletViewModel.accountType,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Account type required'
                      : null,
                ),
                CustomTextField(
                  label: 'Branch Code',
                  hintText: 'Enter branch code',
                  prefixIcon: Icons.numbers,
                  controller: widget.walletViewModel.branchCode,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Branch code required'
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
                                showSnackbar(context, 'Banking details saved ✅',
                                    Colors.green);
                                Navigator.pop(context);
                              } catch (e) {
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
