import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/services/commerce_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/currency_util.dart';

class DropshipListingPage extends StatelessWidget {
  const DropshipListingPage({super.key, required this.product});

  final Product product;

  Future<void> _share(BuildContext context) async {
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
    return Scaffold(
      appBar: const CustomAppBar(title: 'Dropship listing'),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton.icon(
            onPressed: () => _share(context),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share Order on WhatsApp'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: product.image?.isNotEmpty == true
                  ? CachedNetworkImage(
                      imageUrl: product.image!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined, size: 60),
                    )
                  : const ColoredBox(
                      color: Color(0xFFF0F3F2),
                      child: Icon(Icons.inventory_2_outlined, size: 60),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'SUPPLIER FULFILLED',
            style: TextStyle(
              color: Colors.green,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            product.name ?? 'Product',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          if (product.description?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(product.description!),
          ],
          const Divider(height: 32),
          _Line(
            label: 'Estimated landed cost',
            value: CurrencyUtil.format(product.cost ?? 0),
          ),
          _Line(
            label: 'Buyer price from',
            value: CurrencyUtil.format(product.sellingPrice ?? 0),
            emphasized: true,
          ),
          _Line(
            label: 'Markup',
            value: CurrencyUtil.format((product.markupMinor ?? 0) / 100),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'The buyer orders inside WhatsApp. Spaza One checks the live South African delivery cost before creating the order request.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          if (product.shippingNotes?.isNotEmpty == true) ...[
            const Divider(height: 32),
            const Text(
              'Shipping notes',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(product.shippingNotes!),
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              value,
              style: TextStyle(
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}
