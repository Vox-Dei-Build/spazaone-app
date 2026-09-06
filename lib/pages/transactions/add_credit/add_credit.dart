import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/transactions/view_model/add_credit_view_model.dart';
import 'package:pasella/pages/transactions/widgets/customer_form_header.dart';
import 'package:pasella/pages/transactions/widgets/product_selection.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/forms/date_row.dart';
import 'package:pasella/shared/widgets/forms/progressive_form_section.dart';
import 'package:pasella/shared/widgets/forms/transaction_form_scaffold.dart';
import 'package:provider/provider.dart';

/// Add Transaction screen — migrated onto [TransactionFormScaffold] so it
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
            title: 'Add to account',
            scaffoldKey: viewModel.scaffoldKey,
            formKey: viewModel.formKey,
            isLoading: viewModel.isLoading,
            isDirty: viewModel.isDirty,
            primaryActionLabel: 'Add to account',
            primaryActionIcon: Icons.arrow_downward_rounded,
            primaryActionColor: SpazaColors.action,
            onPrimaryAction: () => viewModel.addCreditTransaction(context),
            body: CreditTransactionFields(
              customerName: customerName,
              amountController: viewModel.amountController,
              selectedDate: viewModel.selectedDate,
              repaymentDate: viewModel.repaymentDate,
              onDateChanged: viewModel.setSelectedDate,
              onRepaymentDateChanged: viewModel.setRepaymentDate,
              productField: ProductSelectionWidget<AddCreditViewModel>(
                viewModel: viewModel,
              ),
              productCount: viewModel.selectedProducts.length,
              notesController: viewModel.remarksController,
            ),
          );
        },
      ),
    );
  }
}

/// Pay Later inputs with optional item detail kept behind one-tap reveals.
class CreditTransactionFields extends StatelessWidget {
  const CreditTransactionFields({
    super.key,
    required this.customerName,
    required this.amountController,
    required this.selectedDate,
    required this.repaymentDate,
    required this.onDateChanged,
    required this.onRepaymentDateChanged,
    required this.productField,
    required this.notesController,
    this.productCount = 0,
  });

  final String customerName;
  final TextEditingController amountController;
  final DateTime selectedDate;
  final DateTime repaymentDate;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<DateTime> onRepaymentDateChanged;
  final Widget productField;
  final int productCount;
  final TextEditingController notesController;

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
            textInputType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            validator: (value) {
              final amount = double.tryParse(value?.trim() ?? '');
              if (amount == null || amount <= 0) {
                return 'Enter an amount above 0';
              }
              return null;
            },
          ),
          DateRow(
            label: 'Date',
            value: selectedDate,
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
            onPick: onDateChanged,
          ),
          DateRow(
            label: 'Due date',
            value: repaymentDate,
            firstDate: selectedDate,
            lastDate: DateTime(2100),
            onPick: onRepaymentDateChanged,
          ),
          const SizedBox(height: SpazaSpace.md),
          ProgressiveFormSection(
            title: 'Products',
            actionLabel: 'Add products',
            icon: SpazaIcons.products,
            hasValue: productCount > 0,
            badge: productCount == 0 ? null : '$productCount selected',
            child: productField,
          ),
          ProgressiveFormSection(
            title: 'Notes',
            actionLabel: 'Add a note',
            icon: Icons.notes_rounded,
            hasValue: notesController.text.trim().isNotEmpty,
            child: Padding(
              padding: const EdgeInsets.only(bottom: SpazaSpace.md),
              child: TextFormField(
                controller: notesController,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Optional note'),
              ),
            ),
          ),
        ],
      );
}
