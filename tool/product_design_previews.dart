import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pasella/models/commerce/cj_supplier_product.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/sales/widgets/sale_detail_page.dart';
import 'package:pasella/pages/stock/dropship/supplier_catalog_page.dart';
import 'package:pasella/pages/stock/product_report/product_report.dart';
import 'package:pasella/pages/stock/search/widgets/global_search_bar.dart';
import 'package:pasella/pages/stock/search/widgets/search_product_list.dart';
import 'package:pasella/pages/stock/view_model/product_view_model.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/pages/stock/widgets/product_form.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';

/// Local, synthetic data presented with the actual production widgets.
/// No Firebase client or network service is created by these builders.
Map<String, WidgetBuilder> productDesignPreviews() => {
      'Add product': (_) => const _ProductFormPreview(editing: false),
      'Edit product': (_) => const _ProductFormPreview(editing: true),
      'Supplier catalogue': (_) => const _SupplierPreview(),
      'Product search': (_) => const _SearchPreview(),
      'Stock report': (_) => Scaffold(
            appBar: const CustomAppBar(title: 'Stock report'),
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ProductReportsTab(viewModel: _ReportModel(_products())),
            ),
          ),
      'Sale details': (_) => const _SalePreview(),
    };

List<Product> _products() => [
      Product(
          id: 'bread',
          name: 'White bread · 700 g',
          cost: 13,
          sellingPrice: 18.50,
          quantity: 24),
      Product(
          id: 'milk',
          name: 'Full cream milk · 1 L',
          cost: 16,
          sellingPrice: 22,
          quantity: 3),
      Product(
          id: 'maize',
          name: 'Maize meal · 2.5 kg',
          cost: 29,
          sellingPrice: 38,
          quantity: 0),
      Product(id: 'soap', name: 'Laundry soap', cost: 8, sellingPrice: 12),
      Product(
          id: 'kettle',
          name: 'Supplier kettle',
          cost: 180,
          sellingPrice: 240,
          isDropshipListing: true),
    ];

class _ProductFormPreview extends StatefulWidget {
  const _ProductFormPreview({required this.editing, this.initialProduct});
  final Product? initialProduct;
  final bool editing;
  @override
  State<_ProductFormPreview> createState() => _ProductFormPreviewState();
}

class _ProductFormPreviewState extends State<_ProductFormPreview> {
  final _form = GlobalKey<FormState>();
  late final Product _product =
      widget.initialProduct ?? (widget.editing ? _products().first : Product());
  late final _ProductModel _model = _ProductModel(_product);
  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider<ProductViewModel>.value(
        value: _model,
        child: Scaffold(
          appBar: CustomAppBar(
              title: widget.editing ? 'Edit product' : 'Add product'),
          body: ProductForm(
            formKey: _form,
            product: _product,
            loadShopName: () async => 'Neighbourhood Store',
          ),
          bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  icon: const Icon(Icons.check_rounded),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    if (_form.currentState?.validate() ?? false) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content:
                              Text('Preview only. No product was saved.')));
                    }
                  },
                  label: const Text('Check product details'),
                ),
              )),
        ),
      );
}

class _ProductModel extends ChangeNotifier implements ProductViewModel {
  _ProductModel(Product product)
      : nameController = TextEditingController(text: product.name),
        costController = TextEditingController(text: product.cost?.toString()),
        sellingPriceController =
            TextEditingController(text: product.sellingPrice?.toString()),
        quantityController =
            TextEditingController(text: product.quantity?.toString()),
        companyController = TextEditingController(text: product.company),
        descriptionController =
            TextEditingController(text: product.description);
  @override
  TextEditingController nameController;
  @override
  TextEditingController costController;
  @override
  TextEditingController sellingPriceController;
  @override
  TextEditingController quantityController;
  @override
  TextEditingController companyController;
  @override
  TextEditingController descriptionController;
  @override
  bool isLoading = false;
  @override
  String? imageUrl;
  @override
  File? pendingImage;
  @override
  List<String> productGroups = ['Groceries', 'Household', 'Drinks'];
  @override
  bool get hasImage => false;
  @override
  bool get hasUnsavedChanges => true;
  @override
  void markUnsavedChanges() => notifyListeners();
  @override
  void handleImagePick(BuildContext context, Product product) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Photo upload is unavailable in this preview.')));
  }

  @override
  void dispose() {
    for (final controller in [
      nameController,
      costController,
      sellingPriceController,
      quantityController,
      companyController,
      descriptionController
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReportModel implements StockViewModel {
  _ReportModel(this.products);
  @override
  List<Product> products;
  @override
  List<Product> checkLowStock() => products
      .where(
          (p) => !p.isDropshipListing && p.quantity != null && p.quantity! <= 5)
      .toList();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SearchPreview extends StatefulWidget {
  const _SearchPreview();
  @override
  State<_SearchPreview> createState() => _SearchPreviewState();
}

class _SearchPreviewState extends State<_SearchPreview> {
  final _all = _products();
  String _query = '';
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const CustomAppBar(title: 'Product search'),
        body: Column(children: [
          GlobalSearchBar(onSearch: (value) => setState(() => _query = value)),
          Expanded(
              child: SearchProductList(
            products: _all
                .where((p) =>
                    (p.name ?? '').toLowerCase().contains(_query.toLowerCase()))
                .toList(),
            onOpenProduct: (product) => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => product.isDropshipListing
                        ? const _SupplierPreview()
                        : _ProductFormPreview(
                            editing: true, initialProduct: product))),
          )),
        ]),
      );
}

class _SupplierPreview extends StatelessWidget {
  const _SupplierPreview();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const CustomAppBar(title: 'Supplier catalogue'),
        body: SupplierCatalogPage(
          searchCatalog: (
              {required query, required page, required cursor}) async {
            final products = [
              _supplier('kettle', 'Electric kettle', 16000, 'Home'),
              _supplier('bag', 'Everyday backpack', 21000, 'Fashion'),
              _supplier('lamp', 'Rechargeable desk lamp', 19000, 'Electronics'),
              _supplier('organiser', 'Kitchen organiser', 8500, 'Home'),
            ]
                .where((p) => '${p.title} ${p.category}'
                    .toLowerCase()
                    .contains(query.toLowerCase()))
                .toList();
            return CjCatalogPage(
                products: products,
                page: 1,
                totalPages: 1,
                totalProducts: products.length,
                hasMore: false,
                nextCursor: '',
                catalogueRefreshing: false,
                digitalPaymentsEnabled: false);
          },
          loadSavedProducts: () async => [],
          setSavedProduct: (_, {required saved}) async {},
          createListing: (
              {required supplierProductId,
              required supplierVariantId,
              required catalogQuoteVersion,
              required markupMinor}) async {
            throw StateError('This preview cannot create listings.');
          },
        ),
      );
}

CjCatalogProduct _supplier(
        String id, String title, int amount, String category) =>
    CjCatalogProduct(
      id: id,
      sku: id,
      title: title,
      image: '',
      category: category,
      productCostUsdMinor: 600,
      estimatedProductCostMinor: amount,
      deliverableVariantId: '$id-standard',
      estimatedDeliveryCostMinor: 3500,
      estimatedLandedCostMinor: amount + 3500,
      logisticAging: '7–12 days',
      deliveryVerifiedAt: '2026-09-05T08:00:00Z',
      catalogQuoteVersion: 'preview',
    );

class _SalePreview extends StatefulWidget {
  const _SalePreview();
  @override
  State<_SalePreview> createState() => _SalePreviewState();
}

class _SalePreviewState extends State<_SalePreview> {
  final _sale = Sale(
      id: 'preview',
      amount: 1240,
      stockAmount: 450,
      type: 'Cash',
      products: {'bread': 4, 'milk': 2},
      dateAdded: DateTime(2026, 9, 5, 17, 30),
      remarks: 'Afternoon sales recorded at closing.');
  final _productsFuture = Future.value(<String, Map<String, dynamic>>{
    'bread': {'name': 'White bread · 700 g', 'sellingPrice': 18.50},
    'milk': {'name': 'Full cream milk · 1 L', 'sellingPrice': 22},
  });
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const CustomAppBar(title: 'Sale details'),
        body: SaleDetailsContent(
            sale: _sale,
            productsFuture: _productsFuture,
            loadStockInvoicePreview: (_) async => Uint8List(0)),
      );
}
