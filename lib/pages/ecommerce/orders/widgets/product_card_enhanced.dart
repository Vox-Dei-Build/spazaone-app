import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
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
    final qty =
        (quantity is num) ? quantity.toInt() : int.tryParse('$quantity') ?? 0;
    final resolvedLineTotal = lineTotal ?? (unitPrice * qty);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 48,
                height: 48,
                color: SpazaColors.subtle,
                child: imageUrl == null || imageUrl!.isEmpty
                    ? const Icon(SpazaIcons.products,
                        color: SpazaColors.muted, size: 24)
                    : Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            color: SpazaColors.muted),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(productName, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text('$qty × ${CurrencyUtil.format(unitPrice)}',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Text(CurrencyUtil.format(resolvedLineTotal),
                      style: theme.textTheme.titleMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
