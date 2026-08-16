import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/transactions/view_model/add_payment_view_model.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/forms/date_row.dart';
import 'package:pasella/shared/widgets/forms/transaction_form_scaffold.dart';
import 'package:provider/provider.dart';

/// Add Payment screen — migrated onto [TransactionFormScaffold]. The
/// pre-migration version shipped with a `Form` and no `formKey`, which
/// meant the inline validator never blocked submission. The scaffold
/// owns the formKey + validate() gate, closing that hole.
class AddPaymentScreen extends StatelessWidget {
  final String customerName;
  final String customerId;
  final String? mobileNumber;

  const AddPaymentScreen({
    super.key,
    required this.customerName,
    required this.customerId,
    this.mobileNumber,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AddPaymentViewModel(
        customerName: customerName,
        customerId: customerId,
        mobileNumber: mobileNumber,
      ),
      child: Consumer<AddPaymentViewModel>(
        builder: (context, viewModel, child) {
          return TransactionFormScaffold(
            title: 'Record payment for $customerName',
            scaffoldKey: viewModel.scaffoldKey,
            formKey: viewModel.formKey,
            isLoading: viewModel.isLoading,
            isDirty: viewModel.isDirty,
            primaryActionLabel: 'Record payment',
            primaryActionIcon: Icons.arrow_upward,
            primaryActionColor: Colors.green,
            onPrimaryAction: () => viewModel.addPaymentTransaction(context),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomTextField(
                  label: 'Amount',
                  hintText: 'Enter Amount',
                  prefixIcon: Icons.money,
                  controller: viewModel.amountController,
                  textInputType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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
                  label: 'Date of payment',
                  value: viewModel.selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  onPick: viewModel.setSelectedDate,
                ),
                const SizedBox(height: LayoutConstants.spaceLg),
                DropdownButtonFormField<String>(
                  value: viewModel.paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                    prefixIcon: Icon(Icons.payments_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(
                      value: 'bank_transfer',
                      child: Text('Bank transfer'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: viewModel.isLoading
                      ? null
                      : (value) => viewModel.setPaymentMethod(value ?? 'cash'),
                ),
                const SizedBox(height: LayoutConstants.spaceLg),
                TextFormField(
                  controller: viewModel.remarksController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
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
