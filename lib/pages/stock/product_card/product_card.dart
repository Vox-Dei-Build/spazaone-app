import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_details/product_details.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final String docID;

  const ProductCard({Key? key, required this.product, required this.docID})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ProductDetailsPage(
              docID: docID,
              product: product,
            ),
          ),
        );
      },
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.2),
        child: Padding(
          padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onTap: () {
                    if (product.image != null) {
                      showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          child: InteractiveViewer(
                            child: CachedNetworkImage(
                              imageUrl: product.image!,
                              errorWidget: (context, url, error) => const Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  child: SizedBox(
                    height: SizeConfig.heightMultiplier * 12,
                    width: double.infinity,
                    child: (product.image == null)
                        ? Center(
                            child: Icon(
                              Icons.image,
                              size: SizeConfig.imageSizeMultiplier * 15,
                              color: Colors.grey.withOpacity(0.5),
                            ),
                          )
                        : CachedNetworkImage(
                            fit: BoxFit.cover,
                            imageUrl: product.image!,
                            errorWidget: (context, url, error) => Icon(
                              Icons.image,
                              size: SizeConfig.imageSizeMultiplier * 15,
                              color: Colors.grey.withOpacity(0.5),
                            ),
                          ),
                  ),
                ),
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 1),
              Flexible(
                child: Text(
                  formatStringToCamelCase(product.name ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 0.5),
              Flexible(
                child: Text(
                  'Cost: ${CurrencyUtil.format(product.cost ?? 0)}',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.5,
                    color: Colors.black,
                  ),
                ),
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 0.5),
              Flexible(
                child: Text(
                  'Price: ${CurrencyUtil.format(product.sellingPrice ?? 0)}',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.5,
                    color: Colors.black,
                  ),
                ),
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 0.5),
              Flexible(
                child: Text(
                  '${product.quantity ?? ''} in Stock',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.5,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
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
