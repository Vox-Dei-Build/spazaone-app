import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/transactions/view_model/add_payment_view_model.dart';
import 'package:pasella/pages/transactions/widgets/customer_form_header.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/forms/date_row.dart';
import 'package:pasella/shared/widgets/forms/progressive_form_section.dart';
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
            title: 'Record payment',
            scaffoldKey: viewModel.scaffoldKey,
            formKey: viewModel.formKey,
            isLoading: viewModel.isLoading,
            isDirty: viewModel.isDirty,
            primaryActionLabel: 'Record payment',
            primaryActionIcon: Icons.arrow_upward_rounded,
            primaryActionColor: SpazaColors.action,
            onPrimaryAction: () => viewModel.addPaymentTransaction(context),
            body: CustomerPaymentFields(
              customerName: customerName,
              amountController: viewModel.amountController,
              remarksController: viewModel.remarksController,
              selectedDate: viewModel.selectedDate,
              paymentMethod: viewModel.paymentMethod,
              isLoading: viewModel.isLoading,
              onDateChanged: viewModel.setSelectedDate,
              onPaymentMethodChanged: viewModel.setPaymentMethod,
            ),
          );
        },
      ),
    );
  }
}

/// Payment inputs shared by the live form and local synthetic-data previews.
class CustomerPaymentFields extends StatelessWidget {
  const CustomerPaymentFields({
    super.key,
    required this.customerName,
    required this.amountController,
    required this.remarksController,
    required this.selectedDate,
    required this.paymentMethod,
    required this.onDateChanged,
    required this.onPaymentMethodChanged,
    this.isLoading = false,
  });
  final String customerName;
  final TextEditingController amountController;
  final TextEditingController remarksController;
  final DateTime selectedDate;
  final String paymentMethod;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<String> onPaymentMethodChanged;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomerFormHeader(customerName: customerName),
          CustomTextField(
            label: 'Amount',
            hintText: '0.00',
            prefixIcon: Icons.payments_outlined,
            controller: amountController,
            textInputType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            validator: (value) {
              final amount = double.tryParse(value?.trim() ?? '');
              if (amount == null || amount <= 0) {
                return 'Enter an amount above 0';
              }
              return null;
            },
          ),
          DateRow(
            label: 'Date of payment',
            value: selectedDate,
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
            onPick: onDateChanged,
          ),
          const SizedBox(height: LayoutConstants.spaceLg),
          DropdownButtonFormField<String>(
            isExpanded: true,
            itemHeight: null,
            value: paymentMethod,
            decoration: const InputDecoration(
              labelText: 'Payment method',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(
                value: 'bank_transfer',
                child: Text('Bank transfer'),
              ),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: isLoading
                ? null
                : (value) => onPaymentMethodChanged(value ?? 'cash'),
          ),
          const SizedBox(height: LayoutConstants.spaceLg),
          ProgressiveFormSection(
            title: 'Notes',
            actionLabel: 'Add a note',
            icon: Icons.notes_rounded,
            hasValue: remarksController.text.trim().isNotEmpty,
            child: Padding(
              padding: const EdgeInsets.only(bottom: SpazaSpace.md),
              child: TextFormField(
                controller: remarksController,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Optional note'),
              ),
            ),
          ),
        ],
      );
}
