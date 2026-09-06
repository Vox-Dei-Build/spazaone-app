import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
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
    final theme = Theme.of(context);
    Widget row(String k, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  k,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                  child: Text(
                v,
                textAlign: TextAlign.right,
                style: bold
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.bodyMedium,
              )),
            ],
          ),
        );

    final children = <Widget>[];
    if (subtotal > 0) {
      children.add(row('Subtotal', CurrencyUtil.format(subtotal)));
    }
    if (delivery > 0) {
      children.add(row('Delivery', CurrencyUtil.format(delivery)));
    }
    if (discount > 0) {
      children.add(row('Discount', '-${CurrencyUtil.format(discount)}'));
    }
    children.add(const Divider(color: SpazaColors.border));
    children.add(row('Total', CurrencyUtil.format(total), bold: true));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }
}
