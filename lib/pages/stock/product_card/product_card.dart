import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/promote/utils/run_promotion_launcher.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/stock/product_details/product_details.dart';
import 'package:pasella/pages/stock/dropship/dropship_listing_page.dart';
import 'package:pasella/services/commerce_service.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';
import 'package:provider/provider.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final String docID;

  const ProductCard({Key? key, required this.product, required this.docID})
      : super(key: key);

  Future<void> _promote(BuildContext context) {
    return RunPromotionLauncher.launch(
      context,
      viewModel: context.read<PromotionsViewModel>(),
      initialProduct: LinkedProductRef(
        id: docID,
        name: product.name ?? 'Product',
        sellingPrice: product.sellingPrice,
        imageUrl: product.image,
        whatsappListed: product.whatsappListed,
      ),
    );
  }

  Future<void> _shareDropship(BuildContext context) async {
    try {
      await CommerceService.shareToWhatsApp(
        title: product.name ?? 'Product',
      );
    } catch (error) {
      if (context.mounted) showCommerceError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => product.isDropshipListing
                ? DropshipListingPage(product: product)
                : ProductDetailsPage(docID: docID, product: product),
          ),
        );
      },
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        (product.image == null)
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
                        Positioned(
                          right: SizeConfig.imageSizeMultiplier * 1,
                          top: SizeConfig.heightMultiplier * 0.6,
                          child: _StoreListingChip(
                            listed: product.whatsappListed,
                          ),
                        ),
                        if (product.whatsappListed)
                          Positioned(
                            left: SizeConfig.imageSizeMultiplier * 1,
                            bottom: SizeConfig.heightMultiplier * 0.6,
                            child: ElevatedButton.icon(
                              onPressed: () => product.isDropshipListing
                                  ? _shareDropship(context)
                                  : _promote(context),
                              icon: Icon(
                                product.isDropshipListing
                                    ? Icons.share_outlined
                                    : Icons.campaign_outlined,
                                size: 15,
                              ),
                              label: Text(
                                product.isDropshipListing ? 'Share' : 'Promote',
                              ),
                              style: ElevatedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                textStyle: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                      ],
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
                  '${product.isDropshipListing ? 'Est. landed cost' : 'Cost'}: ${CurrencyUtil.format(product.cost ?? 0)}',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.5,
                    color: Colors.black,
                  ),
                ),
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 0.5),
              Flexible(
                child: Text(
                  '${product.isDropshipListing ? 'From' : 'Price'}: ${CurrencyUtil.format(product.sellingPrice ?? 0)}',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.5,
                    color: Colors.black,
                  ),
                ),
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 0.5),
              Flexible(
                child: Text(
                  product.isDropshipListing
                      ? 'Supplier fulfilled'
                      : '${product.quantity ?? ''} in Stock',
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

class _StoreListingChip extends StatelessWidget {
  const _StoreListingChip({required this.listed});

  final bool listed;

  @override
  Widget build(BuildContext context) {
    final color = listed ? Colors.green.shade700 : Colors.grey.shade800;
    final background = listed ? Colors.green.shade50 : Colors.white;

    return Container(
      constraints: const BoxConstraints(maxWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            listed ? Icons.storefront : Icons.lock_outline,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              listed ? 'WhatsApp' : 'Internal',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
