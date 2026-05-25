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
  });

  factory Product.fromMap(Map<String, dynamic> json, String id) => Product(
        id: id,
        name: json["name"] as String?,
        cost: json["cost"] as double?,
        sellingPrice: json["sellingPrice"] as double?,
        group: json["group"] as String?,
        location: json["location"] as String?,
        company: json["company"] as String?,
        quantity: json["quantity"] as int?,
        image: json["image"] as String?,
        description: json["description"] as String?,
        whatsappListed: json["whatsappListed"] == true ||
            json["whatsappEnabled"] == true ||
            json["availableOnWhatsApp"] == true,
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
      };
}
