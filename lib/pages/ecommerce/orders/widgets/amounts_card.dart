import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/utils/currency_util.dart';

class AmountsCard extends StatelessWidget {
  const AmountsCard(
      {super.key,
      required this.subtotal,
      required this.delivery,
      required this.discount,
      required this.total});
  final double subtotal;
  final double delivery;
  final double discount;
  final double total;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    Widget row(String k, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  k,
                  style: TextStyle(
                    fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
                    fontSize: SizeConfig.textMultiplier * 1.7,
                  ),
                ),
              ),
              Text(
                v,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  fontSize: SizeConfig.textMultiplier * (bold ? 1.9 : 1.7),
                ),
              ),
            ],
          ),
        );

    final children = <Widget>[];
    if (subtotal > 0)
      children.add(row('Subtotal', CurrencyUtil.format(subtotal)));
    if (delivery > 0)
      children.add(row('Delivery', CurrencyUtil.format(delivery)));
    if (discount > 0)
      children.add(row('Discount', '-${CurrencyUtil.format(discount)}'));
    children.add(Divider(color: Colors.grey.shade300));
    children.add(row('Total', CurrencyUtil.format(total), bold: true));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }
}
