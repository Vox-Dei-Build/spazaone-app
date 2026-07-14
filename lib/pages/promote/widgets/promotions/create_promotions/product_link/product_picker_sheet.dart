import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/utils/currency_util.dart';

/// Lightweight product summary attached to a promotion as the
/// "linked product" (PAS-UX-rel #5 Option B). Kept intentionally
/// minimal — we store only what the promotion preview, saved-promo
/// detail page, and (future) reports actually need to render. The
/// canonical product document lives in
/// `users/{uid}/products/{productId}` and remains the source of
/// truth; copying these fields onto the promotion lets the promotion
/// keep rendering correctly if the product is later edited or
/// deleted (which is the audit's bar for "link" — preview should
/// not silently degrade).
class LinkedProductRef {
  final String id;
  final String name;
  final double? sellingPrice;
  final String? imageUrl;
  final bool? whatsappListed;

  const LinkedProductRef({
    required this.id,
    required this.name,
    this.sellingPrice,
    this.imageUrl,
    this.whatsappListed,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name.trim(),
        'sellingPrice': sellingPrice,
        'imageUrl': imageUrl,
        if (whatsappListed != null) 'whatsappListed': whatsappListed,
      };

  static LinkedProductRef? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final id = map['id'];
    final name = map['name'];
    if (id is! String || name is! String) return null;
    return LinkedProductRef(
      id: id,
      name: name.trim(),
      sellingPrice: (map['sellingPrice'] as num?)?.toDouble(),
      imageUrl: map['imageUrl'] as String?,
      whatsappListed: map['whatsappListed'] as bool?,
    );
  }
}

/// Modal bottom sheet for picking a single product to attach to a
/// promotion. Reads `users/{currentUid}/products`, lets the merchant
/// search by name, and returns a [LinkedProductRef] on tap.
///
/// Returns null if the merchant dismisses the sheet without picking
/// (back gesture / scrim). The caller is responsible for handling
/// the unlink action separately — this sheet only models the "pick"
/// path; "unlink" lives where the product chip is shown.
class ProductPickerSheet extends StatefulWidget {
  /// Currently linked product, if any. Used to render a "Selected"
  /// indicator on the matching row so the merchant can see what
  /// they previously chose.
  final String? currentlyLinkedProductId;
  final bool whatsappOnly;

  const ProductPickerSheet({
    super.key,
    this.currentlyLinkedProductId,
    this.whatsappOnly = false,
  });

  static Future<LinkedProductRef?> show(
    BuildContext context, {
    String? currentlyLinkedProductId,
    bool whatsappOnly = false,
  }) {
    return showModalBottomSheet<LinkedProductRef>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProductPickerSheet(
        currentlyLinkedProductId: currentlyLinkedProductId,
        whatsappOnly: whatsappOnly,
      ),
    );
  }

  @override
  State<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<ProductPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _products = const [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('products')
          .get();
      if (!mounted) return;
      setState(() {
        _products = snap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load products: $e';
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final available = widget.whatsappOnly
        ? _products.where(_isWhatsAppListed).toList()
        : _products;
    if (_query.trim().isEmpty) return available;
    final q = _query.trim().toLowerCase();
    return available.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      return name.contains(q);
    }).toList();
  }

  bool _isWhatsAppListed(Map<String, dynamic> product) {
    return product['whatsappListed'] == true ||
        product['whatsappEnabled'] == true ||
        product['availableOnWhatsApp'] == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: SizeConfig.imageSizeMultiplier * 4,
          right: SizeConfig.imageSizeMultiplier * 4,
          top: SizeConfig.heightMultiplier * 2,
          // Push content above the keyboard.
          bottom: MediaQuery.of(context).viewInsets.bottom +
              SizeConfig.heightMultiplier * 2,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 1.5),
              Text(
                widget.whatsappOnly ? 'Choose a product' : 'Link a product',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                widget.whatsappOnly
                    ? 'Only products ready for WhatsApp orders are shown.'
                    : 'Pick the product this promotion is about. Its name and '
                        'image will be attached to the saved promotion.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.disabledColor),
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 1.5),
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search products',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 1),
              Expanded(
                child: _buildList(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 48, color: theme.disabledColor),
              const SizedBox(height: 12),
              Text(
                'No products yet',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Add a product to your stock list first — you\'ll then '
                'be able to link it to a promotion.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.disabledColor),
              ),
            ],
          ),
        ),
      );
    }

    final list = _filtered;
    if (list.isEmpty) {
      final hasQuery = _query.trim().isNotEmpty;
      return Center(
        child: Text(
          hasQuery
              ? 'No products match "$_query".'
              : widget.whatsappOnly
                  ? 'No products are ready for WhatsApp orders yet.\n'
                      'Open a product and turn on WhatsApp ordering first.'
                  : 'No products are available.',
          textAlign: TextAlign.center,
          style:
              theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor),
        ),
      );
    }

    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final p = list[i];
        final id = p['id'] as String;
        final name = (p['name'] ?? 'Untitled').toString();
        final price = (p['sellingPrice'] as num?)?.toDouble();
        final image = p['image'] as String?;
        final whatsappListed = _isWhatsAppListed(p);
        final isSelected = id == widget.currentlyLinkedProductId;

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _Thumb(image: image),
          title: Text(
            name,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                price != null ? CurrencyUtil.format(price) : 'No price set',
              ),
              Text(
                whatsappListed
                    ? 'Available in WhatsApp catalogue'
                    : 'Not listed for WhatsApp orders',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: whatsappListed
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                ),
              ),
            ],
          ),
          trailing: isSelected
              ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
              : const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).pop(LinkedProductRef(
              id: id,
              name: name,
              sellingPrice: price,
              imageUrl: image,
              whatsappListed: whatsappListed,
            ));
          },
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? image;
  const _Thumb({this.image});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (image == null || image!.isEmpty) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.inventory_2_outlined, color: theme.disabledColor),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        image!,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 44,
          height: 44,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Icon(Icons.broken_image, color: theme.disabledColor),
        ),
      ),
    );
  }
}
