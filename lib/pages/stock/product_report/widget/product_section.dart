import 'package:flutter/material.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/config/size_config.dart';

class ProductSection extends StatelessWidget {
  final String title;
  final List<Product> products;

  const ProductSection({Key? key, required this.title, required this.products})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return Card(
      margin: EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 1),
      child: ExpansionTile(
        title: Text(
          title,
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 2.2,
            fontWeight: FontWeight.bold,
          ),
        ),
        children: products.map((product) {
          return ListTile(
            title: Text(
              product.name ?? 'Unknown Product',
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.8),
            ),
            subtitle: Text(
              'Quantity: ${product.quantity ?? 0}',
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.6),
            ),
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Cost: ${CurrencyUtil.format(product.cost ?? 0)}',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: SizeConfig.textMultiplier * 1.6,
                  ),
                ),
                Text(
                  'Selling Price: ${CurrencyUtil.format(product.sellingPrice ?? 0)}',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: SizeConfig.textMultiplier * 1.6,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
