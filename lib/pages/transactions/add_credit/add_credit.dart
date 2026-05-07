import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/transactions/view_model/add_credit_view_model.dart';
import 'package:pasella/pages/transactions/widgets/product_selection.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/forms/date_row.dart';
import 'package:pasella/shared/widgets/forms/transaction_form_scaffold.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

/// Add Credit screen — migrated onto [TransactionFormScaffold] so it
/// shares the form structural standards (sticky CTA, real disabled
/// state, unsaved-changes guard, locale-aware date row) with the rest
/// of the transaction/sale forms.
class AddCreditScreen extends StatelessWidget {
  final String customerName;
  final String customerId;
  final String? mobileNumber;

  const AddCreditScreen({
    super.key,
    required this.customerName,
    required this.customerId,
    this.mobileNumber,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AddCreditViewModel(
        customerName: customerName,
        customerId: customerId,
        mobileNumber: mobileNumber,
      ),
      child: Consumer<AddCreditViewModel>(
        builder: (context, viewModel, child) {
          return TransactionFormScaffold(
            title: 'Add Credit for $customerName',
            formKey: viewModel.formKey,
            isLoading: viewModel.isLoading,
            isDirty: viewModel.isDirty,
            primaryActionLabel: 'Add Credit',
            primaryActionIcon: Icons.arrow_downward,
            primaryActionColor: Colors.red,
            totalLabel: Text(
              'Total: ${CurrencyUtil.format(viewModel.calculateTotalAmount())}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPrimaryAction: () => viewModel.addCreditTransaction(context),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomTextField(
                  label: 'Amount',
                  hintText: 'Enter Amount',
                  prefixIcon: Icons.money,
                  controller: viewModel.amountController,
                  textInputType: TextInputType.number,
                  validator: (value) {
                    if (value == null ||
                        value.isEmpty ||
                        double.tryParse(value) == null) {
                      return 'Please enter a valid amount';
                    }
                    return null;
                  },
                ),
                DateRow(
                  label: 'Date of Credit',
                  value: viewModel.selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  onPick: viewModel.setSelectedDate,
                ),
                DateRow(
                  label: 'Repayment Date',
                  value: viewModel.repaymentDate,
                  firstDate: viewModel.selectedDate,
                  lastDate: DateTime(2100),
                  onPick: viewModel.setRepaymentDate,
                ),
                const SizedBox(height: LayoutConstants.spaceMd),
                ProductSelectionWidget<AddCreditViewModel>(viewModel: viewModel),
                const SizedBox(height: LayoutConstants.spaceLg),
                TextFormField(
                  controller: viewModel.remarksController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Remarks/Notes',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      vertical: LayoutConstants.spaceMd,
                      horizontal: LayoutConstants.spaceMd,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
