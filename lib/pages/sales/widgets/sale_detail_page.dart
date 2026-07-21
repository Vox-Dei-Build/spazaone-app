import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/services/store_session.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/pages/sales/widgets/edit_sale.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';

class SaleDetailPage extends StatefulWidget {
  final Sale sale;

  const SaleDetailPage({super.key, required this.sale});

  @override
  _SaleDetailPageState createState() => _SaleDetailPageState();
}

class _SaleDetailPageState extends State<SaleDetailPage> {
  late Sale sale;

  // PAS-UX-15: batched product lookup.
  //
  // Audit found this page rendered one FutureBuilder<DocumentSnapshot>
  // per product entry, each issuing an independent Firestore .get()
  // against /users/<uid>/products/<id>. A sale with 12 line items
  // therefore round-tripped Firestore 12 times in parallel and
  // showed 12 separate spinners that resolved at different frames.
  // We now fetch every product in a single batch (chunked at the
  // Firestore whereIn cap of 30) and keep the result in a map keyed
  // by product id.
  late final Future<Map<String, Map<String, dynamic>>> _productsFuture;

  @override
  void initState() {
    super.initState();
    sale = widget.sale; // Initialize with the passed sale data
    _productsFuture = _fetchProducts(sale.products.keys.toList());
  }

  /// Fetches every product referenced by [productIds] in a single
  /// batched query (chunked by Firestore's 30-element whereIn cap).
  /// Returns a map keyed by product id; missing ids are simply
  /// absent from the map and rendered as 'Unknown product' below.
  Future<Map<String, Map<String, dynamic>>> _fetchProducts(
      List<String> productIds) async {
    if (productIds.isEmpty) return const {};
    final uid = StoreSession.instance.storeId;
    if (uid.isEmpty) return const {};

    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('products');

    // Chunk to honour Firestore's 30-element whereIn limit. In
    // practice merchants rarely break 10 line items per sale but
    // we chunk defensively so this doesn't silently drop products
    // off long sales.
    const chunkSize = 30;
    final result = <String, Map<String, dynamic>>{};
    for (var i = 0; i < productIds.length; i += chunkSize) {
      final end = (i + chunkSize < productIds.length)
          ? i + chunkSize
          : productIds.length;
      final chunk = productIds.sublist(i, end);
      final snap = await col.where(FieldPath.documentId, whereIn: chunk).get();
      for (final doc in snap.docs) {
        result[doc.id] = doc.data();
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Sale Details',
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () async {
            // EditSale returns `true` when the sale was deleted — close
            // this details screen too since there is nothing left to view.
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (context) => EditSale(
                  sale: sale,
                ),
              ),
            );
            if (result == true && context.mounted) {
              Navigator.of(context).pop(true);
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: LayoutConstants.padding10Horizontal,
          child: ListView(
            children: [
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2.5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        title: Text(
                          'Amount',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: SizeConfig.textMultiplier * 2,
                          ),
                        ),
                        subtitle: Text(
                          CurrencyUtil.format(sale.amount),
                          style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 1.8),
                        ),
                      ),
                      ListTile(
                        title: Text(
                          'Date',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: SizeConfig.textMultiplier * 2,
                          ),
                        ),
                        subtitle: Text(
                          DateFormat("dd-MM-yyyy HH:mm").format(sale.dateAdded),
                          style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 1.8),
                        ),
                      ),
                      ListTile(
                        title: Text(
                          'Type',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: SizeConfig.textMultiplier * 2,
                          ),
                        ),
                        subtitle: Text(
                          sale.type,
                          style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 1.8),
                        ),
                      ),
                      ListTile(
                        title: Text(
                          'Remarks',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: SizeConfig.textMultiplier * 2,
                          ),
                        ),
                        subtitle: Text(
                          sale.remarks ?? 'No Remarks',
                          style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 1.8),
                        ),
                      ),
                      ListTile(
                        title: Text(
                          'Products',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: SizeConfig.textMultiplier * 2,
                          ),
                        ),
                        subtitle: sale.products.isNotEmpty
                            ? FutureBuilder<Map<String, Map<String, dynamic>>>(
                                future: _productsFuture,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Center(
                                          child: CircularProgressIndicator()),
                                    );
                                  }
                                  final products = snapshot.data ?? const {};
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children:
                                        sale.products.entries.map((entry) {
                                      final productId = entry.key;
                                      final quantity = entry.value;
                                      final productData = products[productId];
                                      if (productData == null) {
                                        return Text(
                                            'Unknown product with ID: $productId');
                                      }
                                      final productName = productData['name'] ??
                                          'Unnamed product';
                                      final sellingPrice =
                                          productData['sellingPrice'];

                                      return Card(
                                        elevation: 2,
                                        margin: EdgeInsets.symmetric(
                                          vertical:
                                              SizeConfig.heightMultiplier * 1,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.all(
                                              SizeConfig.imageSizeMultiplier *
                                                  2),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.inventory,
                                                    size: SizeConfig
                                                            .imageSizeMultiplier *
                                                        4,
                                                  ),
                                                  SizedBox(
                                                      width: SizeConfig
                                                              .imageSizeMultiplier *
                                                          2),
                                                  Expanded(
                                                    child: Text(
                                                      formatStringToCamelCase(
                                                          productName),
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: SizeConfig
                                                                .textMultiplier *
                                                            2,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              SizedBox(
                                                  height: SizeConfig
                                                          .heightMultiplier *
                                                      1),
                                              Text(
                                                'Quantity: $quantity',
                                                style: TextStyle(
                                                  fontSize: SizeConfig
                                                          .textMultiplier *
                                                      1.8,
                                                ),
                                              ),
                                              SizedBox(
                                                  height: SizeConfig
                                                          .heightMultiplier *
                                                      0.5),
                                              Text(
                                                'Selling Price: ${CurrencyUtil.format(sellingPrice)}',
                                                style: TextStyle(
                                                  fontStyle: FontStyle.italic,
                                                  fontSize: SizeConfig
                                                          .textMultiplier *
                                                      1.8,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              )
                            : Text(
                                'No products associated with this sale.',
                                style: TextStyle(
                                    fontSize: SizeConfig.textMultiplier * 2),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
