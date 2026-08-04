class Product {
  String? id;
  String? name;
  double? cost;
  double? sellingPrice;
  String? group;
  String? location;
  String? company;
  int? quantity;
  String? image;
  String? description;
  bool whatsappListed;
  String? supplierId;
  String? sourceProductId;
  String? sourceVariantId;
  String? supplierSku;
  String? curatedProductId;
  String? fulfilmentMode;
  String? shippingNotes;
  bool isDropshipListing;
  String? commerceListingId;
  String? checkoutUrl;
  int? baseCostMinor;
  int? supplierProductCostMinor;
  int? supplierShippingCostMinor;
  int? markupMinor;
  int? sellPriceMinor;

  Product({
    this.id,
    this.name,
    this.cost,
    this.sellingPrice,
    this.group,
    this.location,
    this.company,
    this.quantity,
    this.image,
    this.description,
    this.whatsappListed = false,
    this.supplierId,
    this.sourceProductId,
    this.sourceVariantId,
    this.supplierSku,
    this.curatedProductId,
    this.fulfilmentMode,
    this.shippingNotes,
    this.isDropshipListing = false,
    this.commerceListingId,
    this.checkoutUrl,
    this.baseCostMinor,
    this.supplierProductCostMinor,
    this.supplierShippingCostMinor,
    this.markupMinor,
    this.sellPriceMinor,
  });

  static double? _double(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  static int? _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value');

  factory Product.fromMap(Map<String, dynamic> json, String id) => Product(
        id: id,
        name: json["name"] as String?,
        cost: _double(json["cost"]),
        sellingPrice: _double(json["sellingPrice"]),
        group: json["group"] as String?,
        location: json["location"] as String?,
        company: json["company"] as String?,
        quantity: _int(json["quantity"]),
        image: json["image"] as String?,
        description: json["description"] as String?,
        whatsappListed: json["whatsappListed"] == true ||
            json["whatsappEnabled"] == true ||
            json["availableOnWhatsApp"] == true,
        supplierId: json["supplierId"] as String?,
        sourceProductId: json["sourceProductId"] as String?,
        sourceVariantId: json["sourceVariantId"] as String?,
        supplierSku: json["supplierSku"] as String?,
        curatedProductId: json["curatedProductId"] as String?,
        fulfilmentMode: json["fulfilmentMode"] as String?,
        shippingNotes: json["shippingNotes"] as String?,
        isDropshipListing: json["isDropshipListing"] == true,
        commerceListingId: json["commerceListingId"] as String?,
        checkoutUrl: json["checkoutUrl"] as String?,
        baseCostMinor: _int(json["baseCostMinor"]),
        supplierProductCostMinor: _int(json["supplierProductCostMinor"]),
        supplierShippingCostMinor: _int(json["supplierShippingCostMinor"]),
        markupMinor: _int(json["markupMinor"]),
        sellPriceMinor: _int(json["sellPriceMinor"]),
      );

  Map<String, dynamic> toMap() => {
        "name": name,
        "cost": cost,
        "sellingPrice": sellingPrice,
        "group": group,
        "location": location,
        "company": company,
        "quantity": quantity,
        "image": image,
        "description": description,
        "whatsappListed": whatsappListed,
        if (supplierId != null) "supplierId": supplierId,
        if (sourceProductId != null) "sourceProductId": sourceProductId,
        if (sourceVariantId != null) "sourceVariantId": sourceVariantId,
        if (supplierSku != null) "supplierSku": supplierSku,
        if (curatedProductId != null) "curatedProductId": curatedProductId,
        if (fulfilmentMode != null) "fulfilmentMode": fulfilmentMode,
        if (shippingNotes != null) "shippingNotes": shippingNotes,
        "isDropshipListing": isDropshipListing,
        if (commerceListingId != null) "commerceListingId": commerceListingId,
        if (checkoutUrl != null) "checkoutUrl": checkoutUrl,
        if (baseCostMinor != null) "baseCostMinor": baseCostMinor,
        if (supplierProductCostMinor != null)
          "supplierProductCostMinor": supplierProductCostMinor,
        if (supplierShippingCostMinor != null)
          "supplierShippingCostMinor": supplierShippingCostMinor,
        if (markupMinor != null) "markupMinor": markupMinor,
        if (sellPriceMinor != null) "sellPriceMinor": sellPriceMinor,
      };
}
