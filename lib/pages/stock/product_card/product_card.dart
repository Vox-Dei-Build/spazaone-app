import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/promote/utils/linked_product_promotion.dart';
import 'package:pasella/pages/stock/product_details/product_details.dart';
import 'package:pasella/pages/stock/dropship/dropship_listing_page.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final String docID;
  final LinkedProductPromotionLauncher promotionLauncher;
  final bool compactHorizontal;

  const ProductCard({
    Key? key,
    required this.product,
    required this.docID,
    this.promotionLauncher = launchLinkedProductPromotion,
    this.compactHorizontal = false,
  }) : super(key: key);

  Future<void> _promote(BuildContext context) {
    return promotionLauncher(
      context,
      promotionProductRef(product, docID),
    );
  }

  void _openDetails(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => product.isDropshipListing
            ? DropshipListingPage(
                product: product,
                docID: docID,
                promotionLauncher: promotionLauncher,
              )
            : ProductDetailsPage(docID: docID, product: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    if (compactHorizontal) {
      return GestureDetector(
        onTap: () => _openDetails(context),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: .12),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox.square(
                    dimension: 82,
                    child: product.image == null
                        ? ColoredBox(
                            color: Colors.grey.withValues(alpha: .10),
                            child: const Icon(
                              Icons.image_outlined,
                              color: Colors.grey,
                            ),
                          )
                        : CachedNetworkImage(
                            fit: BoxFit.cover,
                            imageUrl: product.image!,
                            errorWidget: (_, __, ___) => const ColoredBox(
                              color: Color(0xFFF2F2F2),
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatStringToCamelCase(product.name ?? ''),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${product.isDropshipListing ? 'From' : 'Price'}: ${CurrencyUtil.format(product.sellingPrice ?? 0)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        product.isDropshipListing
                            ? 'Supplier fulfilled'
                            : '${product.quantity ?? ''} in stock',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFF2B325F),
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 21),
              ],
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _openDetails(context),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.2),
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
                                  color: Colors.grey.withValues(alpha: 0.5),
                                ),
                              )
                            : CachedNetworkImage(
                                fit: BoxFit.cover,
                                imageUrl: product.image!,
                                errorWidget: (context, url, error) => Icon(
                                  Icons.image,
                                  size: SizeConfig.imageSizeMultiplier * 15,
                                  color: Colors.grey.withValues(alpha: 0.5),
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
                              onPressed: () => _promote(context),
                              icon: const Icon(
                                Icons.campaign_outlined,
                                size: 15,
                              ),
                              label: const Text('Promote'),
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
