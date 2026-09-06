import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/models/stock/product_model.dart';

class ProductSection extends StatelessWidget {
  final String title;
  final List<Product> products;

  const ProductSection({Key? key, required this.title, required this.products})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        if (products.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Stock levels look good.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          )
        else
          ...products.map((product) {
            final quantity = product.quantity ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(SpazaIcons.products, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name ?? 'Unknown product',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 6),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            Text(quantity == 0 ? 'Out of stock' : 'Low stock',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: quantity == 0
                                            ? SpazaColors.error
                                            : const Color(0xFF906000))),
                            Text(
                                quantity == 0
                                    ? 'No stock left'
                                    : 'Only $quantity left',
                                style: Theme.of(context).textTheme.bodySmall),
                          ]),
                        ],
                      )),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
