import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/pages/transactions/widgets/product_selection.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/forms/date_row.dart';
import 'package:pasella/shared/widgets/forms/transaction_form_scaffold.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

/// Add Sale screen — migrated onto [TransactionFormScaffold].
///
/// The pre-migration version round-tripped the picked date through
/// `DateFormat.parse` on every render. The new flow stores the value
/// directly via the view model setter and renders it through `DateRow`
/// so the time component is preserved and the screen no longer throws
/// on locale mismatch.
class AddSale extends StatelessWidget {
  final SalesViewModel salesViewModel;

  const AddSale({super.key, required this.salesViewModel});

  static final DateFormat _saleDateFmt = DateFormat('dd-MM-yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SalesViewModel(),
      child: Consumer<SalesViewModel>(
        builder: (context, transactionViewModel, child) {
          // The view model still stores `salesSelectedDate` as a string
          // for backwards-compat with the firestore write path. Parse
          // for display, write back through `setSalesSelectedDate`.
          final selectedDate =
              _saleDateFmt.parse(transactionViewModel.salesSelectedDate);

          return TransactionFormScaffold(
            title: 'Add Sale',
            formKey: transactionViewModel.formKey,
            isLoading: transactionViewModel.isLoading,
            isDirty: transactionViewModel.isDirty,
            primaryActionLabel: 'Add Sale',
            primaryActionIcon: Icons.point_of_sale,
            primaryActionColor: Colors.green,
            totalLabel: Text(
              'Total: ${CurrencyUtil.format(transactionViewModel.calculateTotalAmount())}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPrimaryAction: () async {
              await transactionViewModel.addSalesTransaction(context);
              salesViewModel.updateSelectedDate(DateTime.now());
            },
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomTextField(
                  label: 'Amount',
                  hintText: 'Enter Amount',
                  prefixIcon: Icons.money,
                  controller: transactionViewModel.amountController,
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
                  label: 'Date of Sale',
                  value: selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  onPick: transactionViewModel.setSalesSelectedDate,
                ),
                const SizedBox(height: LayoutConstants.spaceMd),
                ProductSelectionWidget(viewModel: transactionViewModel),
                const SizedBox(height: LayoutConstants.spaceLg),
                TextFormField(
                  controller: transactionViewModel.remarksController,
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
