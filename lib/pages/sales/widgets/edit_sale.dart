import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/pages/sales/widgets/stock_amount_field.dart';
import 'package:pasella/pages/sales/widgets/stock_invoice_attachments_field.dart';
import 'package:pasella/pages/transactions/widgets/product_selection.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/forms/confirm_dialog.dart';
import 'package:pasella/shared/widgets/forms/date_row.dart';
import 'package:pasella/shared/widgets/forms/transaction_form_scaffold.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

/// Edit Sale screen — migrated onto [TransactionFormScaffold].
///
/// Adds destructive confirms for both Update and Delete (the audit
/// found neither existed previously) and removes the legacy
/// `setState`-inside-Provider mixed-state-model that was unique to this
/// screen. Date handling now goes through the view model setter so the
/// time component survives picks and the screen does not throw on
/// locale mismatch.
class EditSale extends StatelessWidget {
  final Sale sale;

  const EditSale({super.key, required this.sale});

  static final DateFormat _saleDateFmt = DateFormat('dd-MM-yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SalesViewModel()..loadSaleDetails(sale),
      child: Consumer<SalesViewModel>(
        builder: (context, transactionViewModel, child) {
          final selectedDate = _saleDateFmt.parse(
            transactionViewModel.salesSelectedDate,
          );

          return TransactionFormScaffold(
            title: 'Edit sale',
            scaffoldKey: transactionViewModel.scaffoldKey,
            formKey: transactionViewModel.formKey,
            isLoading: transactionViewModel.isLoading,
            isDirty: transactionViewModel.isDirty,
            primaryActionLabel: 'Update sale',
            primaryActionIcon: Icons.point_of_sale,
            primaryActionColor: SpazaColors.action,
            totalLabel: Text(
              'Total: ${CurrencyUtil.format(transactionViewModel.calculateTotalAmount())}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            onPrimaryAction: () async {
              final confirmed = await ConfirmDialog.show(
                context,
                title: 'Update sale?',
                message: 'This will overwrite the existing sale record.',
                confirmLabel: 'Update',
              );
              if (!confirmed) return;
              if (!context.mounted) return;
              await transactionViewModel.updateSale(
                sale,
                double.tryParse(transactionViewModel.amountController.text) ??
                    0.0,
                transactionViewModel.selectedProducts,
                context,
              );
            },
            onDelete: () => transactionViewModel.deleteSale(context, sale),
            deleteConfirmTitle: 'Delete sale?',
            deleteConfirmMessage:
                'This permanently removes the sale and returns its stock to inventory.',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomTextField(
                  label: 'Amount',
                  hintText: 'Enter amount',
                  prefixIcon: Icons.money,
                  controller: transactionViewModel.amountController,
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
                StockAmountField(
                  controller: transactionViewModel.stockAmountController,
                ),
                StockInvoiceAttachmentsField(
                  attachments: transactionViewModel.stockInvoiceDrafts,
                  onAdd: () => transactionViewModel.addStockInvoice(context),
                  onRemove: transactionViewModel.removeStockInvoice,
                  onReplace: (index) =>
                      transactionViewModel.replaceStockInvoice(context, index),
                  onRetry: transactionViewModel.retryStockInvoice,
                  loadPreview: transactionViewModel.loadStockInvoicePreview,
                ),
                DateRow(
                  label: 'Date of sale',
                  value: selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  onPick: transactionViewModel.setSalesSelectedDate,
                ),
                const SizedBox(height: LayoutConstants.spaceMd),
                if (transactionViewModel.isTransactionLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: LayoutConstants.spaceXl,
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(SpazaColors.action),
                      ),
                    ),
                  )
                else
                  ProductSelectionWidget(viewModel: transactionViewModel),
                const SizedBox(height: LayoutConstants.spaceLg),
                TextFormField(
                  controller: transactionViewModel.remarksController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
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
