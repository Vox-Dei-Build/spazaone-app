import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/utils/currency_util.dart';

class ProductCardEnhanced extends StatelessWidget {
  const ProductCardEnhanced({
    super.key,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.imageUrl,
    this.lineTotal,
  });

  final String productName;
  final dynamic quantity;
  final double unitPrice;
  final String? imageUrl;
  final double? lineTotal;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final qty =
        (quantity is num) ? quantity.toInt() : int.tryParse('$quantity') ?? 0;

    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 2.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: SizeConfig.imageSizeMultiplier * 14,
                    height: SizeConfig.imageSizeMultiplier * 14,
                    color: Colors.grey.shade200,
                    child: imageUrl == null || imageUrl!.isEmpty
                        ? Icon(Icons.inventory_2,
                            size: SizeConfig.imageSizeMultiplier * 7,
                            color: Colors.grey.shade600)
                        : Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.broken_image,
                                color: Colors.grey.shade600),
                          ),
                  ),
                ),
                Positioned(
                  right: -2,
                  top: -2,
                  child: CircleAvatar(
                    radius: SizeConfig.imageSizeMultiplier * 3.8,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text('x$qty',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: SizeConfig.textMultiplier * 1.3)),
                  ),
                ),
              ],
            ),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: SizeConfig.textMultiplier * 1.9),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 0.6),
                  Text('Unit: ${CurrencyUtil.format(unitPrice)}',
                      style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 1.6,
                          color: Colors.grey.shade700)),
                ],
              ),
            ),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
            if (lineTotal != null)
              Text(
                CurrencyUtil.format(lineTotal!),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: SizeConfig.textMultiplier * 1.9),
              ),
          ],
        ),
      ),
    );
  }
}
