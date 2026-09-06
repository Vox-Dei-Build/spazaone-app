import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/promote/utils/linked_product_promotion.dart';
import 'package:pasella/services/commerce_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/currency_util.dart';

typedef DropshipListingUpdater = Future<DropshipListingUpdateResult> Function({
  required String sellerProductId,
  required String listingId,
  required int markupMinor,
  required String state,
});

Future<DropshipListingUpdateResult> _updateDropshipListing({
  required String sellerProductId,
  required String listingId,
  required int markupMinor,
  required String state,
}) =>
    CommerceService().updateDropshipListing(
      sellerProductId: sellerProductId,
      listingId: listingId,
      markupMinor: markupMinor,
      state: state,
    );

class DropshipListingPage extends StatefulWidget {
  DropshipListingPage({
    super.key,
    required this.product,
    required this.docID,
    this.promotionLauncher = launchLinkedProductPromotion,
    DropshipListingUpdater? listingUpdater,
  }) : listingUpdater = listingUpdater ?? _updateDropshipListing;

  final Product product;
  final String docID;
  final LinkedProductPromotionLauncher promotionLauncher;
  final DropshipListingUpdater listingUpdater;

  @override
  State<DropshipListingPage> createState() => _DropshipListingPageState();
}

class _DropshipListingPageState extends State<DropshipListingPage> {
  late int _markupMinor;
  late int _sellPriceMinor;
  late String _listingState;

  Product get product => widget.product;

  @override
  void initState() {
    super.initState();
    _markupMinor = product.markupMinor ?? 0;
    _sellPriceMinor =
        product.sellPriceMinor ?? ((product.sellingPrice ?? 0) * 100).round();
    final storedState = product.dropshipListingState?.trim().toLowerCase();
    _listingState = const {'active', 'internal', 'paused'}.contains(storedState)
        ? storedState!
        : product.whatsappListed
            ? 'active'
            : 'internal';
  }

  Future<void> _promote(BuildContext context) {
    return widget.promotionLauncher(
      context,
      promotionProductRef(product, widget.docID),
    );
  }

  String get _stateLabel => switch (_listingState) {
        'active' => 'Active on storefront',
        'paused' => 'Paused',
        _ => 'Internal only',
      };

  String _errorMessage(Object error) {
    if (error is FirebaseFunctionsException &&
        error.message?.trim().isNotEmpty == true) {
      return error.message!.trim();
    }
    return 'The supplier listing could not be updated. Try again.';
  }

  Future<void> _editListing() async {
    final listingId = product.commerceListingId?.trim() ?? '';
    if (listingId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This older listing cannot be edited yet.'),
        ),
      );
      return;
    }
    final markup = TextEditingController(
      text: (_markupMinor / 100).toStringAsFixed(2),
    );
    var selectedState = _listingState;
    var saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit supplier product'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey('edit-dropship-markup'),
                  controller: markup,
                  enabled: !saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Markup',
                    prefixText: 'R ',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const ValueKey('edit-dropship-state'),
                  value: selectedState,
                  decoration: const InputDecoration(
                    labelText: 'Availability',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'active',
                      child: Text('Active on storefront'),
                    ),
                    DropdownMenuItem(
                      value: 'internal',
                      child: Text('Internal only'),
                    ),
                    DropdownMenuItem(
                      value: 'paused',
                      child: Text('Paused'),
                    ),
                  ],
                  onChanged: saving
                      ? null
                      : (value) {
                          if (value != null) selectedState = value;
                        },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Internal only removes it from the storefront but keeps it in inventory. Paused also keeps it hidden until you reactivate it.',
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    key: const ValueKey('edit-dropship-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('save-dropship-listing'),
              onPressed: saving
                  ? null
                  : () async {
                      final amount = double.tryParse(
                        markup.text.trim().replaceAll(',', '.'),
                      );
                      if (amount == null || amount <= 0) {
                        setDialogState(
                          () => error = 'Enter a markup greater than zero.',
                        );
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final result = await widget.listingUpdater(
                          sellerProductId: widget.docID,
                          listingId: listingId,
                          markupMinor: (amount * 100).round(),
                          state: selectedState,
                        );
                        if (!mounted || !dialogContext.mounted) return;
                        setState(() {
                          _markupMinor = result.markupMinor;
                          _sellPriceMinor = result.sellPriceMinor;
                          _listingState = result.state;
                          product.markupMinor = result.markupMinor;
                          product.sellPriceMinor = result.sellPriceMinor;
                          product.sellingPrice = result.sellPriceMinor / 100;
                          product.whatsappListed = result.state == 'active';
                          product.dropshipListingState = result.state;
                        });
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('Listing updated.')),
                        );
                      } catch (caught) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          saving = false;
                          error = _errorMessage(caught);
                        });
                      }
                    },
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    // The dialog future completes when pop starts; retain the controller until
    // its exit transition has detached the text field.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    markup.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Product'),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stackActions = constraints.maxWidth < 420 ||
                  MediaQuery.textScalerOf(context).scale(14) >= 18;
              final edit = OutlinedButton.icon(
                key: const ValueKey('edit-dropship-listing'),
                onPressed: _editListing,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit listing'),
              );
              final promote = ElevatedButton.icon(
                key: const ValueKey('promote-dropship-listing'),
                onPressed:
                    _listingState == 'active' ? () => _promote(context) : null,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Promote on WhatsApp'),
              );

              if (stackActions) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    edit,
                    const SizedBox(height: 8),
                    promote,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: edit),
                  const SizedBox(width: 10),
                  Expanded(child: promote),
                ],
              );
            },
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(SpazaRadius.surface),
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
                      color: SpazaColors.subtle,
                      child: Icon(Icons.inventory_2_outlined, size: 60),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'SUPPLIER FULFILLED',
            style: TextStyle(
              color: SpazaColors.action,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _stateLabel,
            key: const ValueKey('dropship-listing-state'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            product.name ?? 'Product',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
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
            value: CurrencyUtil.format(_sellPriceMinor / 100),
            emphasized: true,
          ),
          _Line(
            label: 'Markup',
            value: CurrencyUtil.format(_markupMinor / 100),
          ),
          if (product.shippingNotes?.isNotEmpty == true) ...[
            const Divider(height: 32),
            const Text(
              'Shipping notes',
              style: TextStyle(fontWeight: FontWeight.w500),
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
                fontWeight: emphasized ? FontWeight.w500 : FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}
