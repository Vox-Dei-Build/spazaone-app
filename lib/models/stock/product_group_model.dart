import 'package:cloud_firestore/cloud_firestore.dart';

class ProductGroup {
  String? name;
  Timestamp? createdAt;

  ProductGroup({
    this.name,
    this.createdAt,
  });

  factory ProductGroup.fromMap(Map<String, dynamic> json) => ProductGroup(
        name: json["name"] as String?,
        createdAt: json["createdAt"] as Timestamp?,
      );

  Map<String, dynamic> toMap() => {
        "name": name,
        "createdAt": createdAt,
      };
}
