import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/transactions/view_model/edit_transaction_view_model.dart';
import 'package:pasella/pages/transactions/widgets/product_selection.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/forms/confirm_dialog.dart';
import 'package:pasella/shared/widgets/forms/date_row.dart';
import 'package:pasella/shared/widgets/forms/transaction_form_scaffold.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

/// Edit Transaction screen — migrated onto [TransactionFormScaffold].
///
/// Fixes from the audit:
/// - missing `formKey` is now provided by the scaffold;
/// - the stray "Repayment Date" row that rendered for non-credit
///   transactions is gated behind `isCredit`;
/// - destructive actions (Update, Delete) now confirm before committing;
/// - unsaved-changes guard via the scaffold's `PopScope`.
class EditTransactionScreen extends StatelessWidget {
  final String customerName;
  final String customerId;
  final String transactionId;
  final Map<String, dynamic> transaction;
  final String? mobileNumber;

  const EditTransactionScreen({
    super.key,
    required this.customerName,
    required this.customerId,
    required this.transactionId,
    required this.transaction,
    this.mobileNumber,
  });

  @override
  Widget build(BuildContext context) {
    final transactionType = transaction['type'] as String;
    final bool isCredit = transactionType == 'Credit';

    return ChangeNotifierProvider(
      create: (_) => EditTransactionViewModel(
        customerName: customerName,
        customerId: customerId,
        transaction: transaction,
        transactionId: transactionId,
        transactionType: transactionType,
        mobileNumber: mobileNumber,
      ),
      child: Consumer<EditTransactionViewModel>(
        builder: (context, viewModel, child) {
          return TransactionFormScaffold(
            title: 'Edit $transactionType for $customerName',
            formKey: viewModel.formKey,
            isLoading: viewModel.isLoading,
            isDirty: viewModel.isDirty,
            primaryActionLabel: 'Update $transactionType',
            primaryActionIcon:
                isCredit ? Icons.arrow_downward : Icons.arrow_upward,
            primaryActionColor: isCredit ? Colors.red : Colors.green,
            totalLabel: isCredit
                ? Text(
                    'Total: ${CurrencyUtil.format(viewModel.calculateTotalAmount())}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
            onPrimaryAction: () async {
              final confirmed = await ConfirmDialog.show(
                context,
                title: 'Update $transactionType?',
                message:
                    'This will overwrite the existing $transactionType record for $customerName.',
                confirmLabel: 'Update',
              );
              if (!confirmed) return;
              if (!context.mounted) return;
              await viewModel.updateTransaction(context);
            },
            onDelete: () => viewModel.deleteTransaction(context),
            deleteConfirmTitle: 'Delete $transactionType?',
            deleteConfirmMessage:
                'This permanently removes the $transactionType for $customerName${isCredit ? ' and returns reserved stock to inventory' : ''}.',
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
                if (isCredit)
                  DateRow(
                    label: 'Date of Credit',
                    value: viewModel.selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    onPick: viewModel.setSelectedDate,
                  )
                else
                  DateRow(
                    label: 'Date of Payment',
                    value: viewModel.selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    onPick: viewModel.setSelectedDate,
                  ),
                if (isCredit)
                  DateRow(
                    label: 'Repayment Date',
                    value: viewModel.repaymentDate,
                    firstDate: viewModel.selectedDate,
                    lastDate: DateTime(2100),
                    onPick: viewModel.setRepaymentDate,
                  ),
                if (isCredit) ...[
                  const SizedBox(height: LayoutConstants.spaceMd),
                  if (viewModel.isProductsLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                          vertical: LayoutConstants.spaceXl),
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.green),
                        ),
                      ),
                    )
                  else
                    ProductSelectionWidget<EditTransactionViewModel>(
                        viewModel: viewModel),
                ],
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
