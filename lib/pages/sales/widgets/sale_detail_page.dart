import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  @override
  void initState() {
    super.initState();
    sale = widget.sale; // Initialize with the passed sale data
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
            // Navigate to EditSale and await the result
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => EditSale(
                  sale: sale,
                ),
              ),
            );
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
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: sale.products.entries.map((entry) {
                                  final productId = entry.key;
                                  final quantity = entry.value;

                                  return FutureBuilder<DocumentSnapshot>(
                                    future: FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(FirebaseAuth
                                                .instance.currentUser?.uid ??
                                            '')
                                        .collection('products')
                                        .doc(productId)
                                        .get(),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const CircularProgressIndicator();
                                      }
                                      if (snapshot.hasError) {
                                        return Text(
                                            'Error fetching product with ID: $productId');
                                      }
                                      if (!snapshot.hasData ||
                                          !snapshot.data!.exists) {
                                        return Text(
                                            'Unknown product with ID: $productId');
                                      }
                                      final productData = snapshot.data!.data()
                                          as Map<String, dynamic>;
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
                                          padding: EdgeInsets.all(SizeConfig
                                                  .imageSizeMultiplier *
                                              2), // Add padding to avoid overflow
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
                                                      1), // Add some spacing
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
                                                      0.5), // Add some spacing
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
                                    },
                                  );
                                }).toList(),
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
