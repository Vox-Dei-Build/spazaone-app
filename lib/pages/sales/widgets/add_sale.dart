import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/pages/sales/widgets/stock_amount_field.dart';
import 'package:pasella/pages/sales/widgets/stock_invoice_attachments_field.dart';
import 'package:pasella/pages/transactions/widgets/product_selection.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/forms/date_row.dart';
import 'package:pasella/shared/widgets/forms/progressive_form_section.dart';
import 'package:pasella/shared/widgets/forms/transaction_form_scaffold.dart';
import 'package:provider/provider.dart';

/// Add Sale screen — migrated onto [TransactionFormScaffold].
///
/// The pre-migration version round-tripped the picked date through
/// `DateFormat.parse` on every render. The new flow stores the value
/// directly via the view model setter and renders it through `DateRow`
/// so the time component is preserved and the screen no longer throws
/// on locale mismatch.
class AddSale extends StatelessWidget {
  const AddSale({super.key});

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
          final selectedDate = _saleDateFmt.parse(
            transactionViewModel.salesSelectedDate,
          );

          return TransactionFormScaffold(
            title: 'Record sale',
            scaffoldKey: transactionViewModel.scaffoldKey,
            formKey: transactionViewModel.formKey,
            isLoading: transactionViewModel.isLoading,
            isDirty: transactionViewModel.isDirty,
            primaryActionLabel: 'Save sale',
            primaryActionIcon: SpazaIcons.sales,
            onPrimaryAction: () async {
              await transactionViewModel.addSalesTransaction(context);
            },
            body: RecordSaleFields(
              amountController: transactionViewModel.amountController,
              selectedDate: selectedDate,
              onDateChanged: transactionViewModel.setSalesSelectedDate,
              stockAmountController: transactionViewModel.stockAmountController,
              invoiceField: StockInvoiceAttachmentsField(
                attachments: transactionViewModel.stockInvoiceDrafts,
                onAdd: () => transactionViewModel.addStockInvoice(context),
                onRemove: transactionViewModel.removeStockInvoice,
                onReplace: (index) =>
                    transactionViewModel.replaceStockInvoice(context, index),
                onRetry: transactionViewModel.retryStockInvoice,
                loadPreview: transactionViewModel.loadStockInvoicePreview,
              ),
              invoiceCount: transactionViewModel.stockInvoiceDrafts.length,
              productField:
                  ProductSelectionWidget(viewModel: transactionViewModel),
              productCount: transactionViewModel.selectedProducts.length,
              notesController: transactionViewModel.remarksController,
            ),
          );
        },
      ),
    );
  }
}

/// The calm, progressive Record Sale fields used by the live form and tests.
class RecordSaleFields extends StatelessWidget {
  const RecordSaleFields({
    super.key,
    required this.amountController,
    required this.selectedDate,
    required this.onDateChanged,
    required this.stockAmountController,
    required this.invoiceField,
    required this.productField,
    required this.notesController,
    this.invoiceCount = 0,
    this.productCount = 0,
  });

  final TextEditingController amountController;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final TextEditingController stockAmountController;
  final Widget invoiceField;
  final int invoiceCount;
  final Widget productField;
  final int productCount;
  final TextEditingController notesController;

  @override
  Widget build(BuildContext context) {
    final hasRestocking =
        stockAmountController.text.trim().isNotEmpty || invoiceCount > 0;
    final hasNotes = notesController.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomTextField(
          label: 'Sales amount',
          hintText: '0.00',
          prefixIcon: Icons.payments_outlined,
          controller: amountController,
          textInputType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          validator: _positiveAmountValidator,
        ),
        DateRow(
          label: 'Date',
          value: selectedDate,
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
          onPick: onDateChanged,
        ),
        const SizedBox(height: SpazaSpace.md),
        ProgressiveFormSection(
          title: 'Restocking',
          actionLabel: 'Add restocking',
          icon: Icons.inventory_2_outlined,
          hasValue: hasRestocking,
          badge: invoiceCount == 0 ? null : '$invoiceCount attached',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StockAmountField(controller: stockAmountController),
              invoiceField,
            ],
          ),
        ),
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
          hasValue: hasNotes,
          child: Padding(
            padding: const EdgeInsets.only(bottom: LayoutConstants.spaceMd),
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
}

String? _positiveAmountValidator(String? value) {
  final amount = double.tryParse(value?.trim() ?? '');
  if (amount == null || amount <= 0) return 'Enter an amount above 0';
  return null;
}
