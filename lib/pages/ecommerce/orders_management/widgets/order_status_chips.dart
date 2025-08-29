import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';

class OrderStatusChips extends StatelessWidget {
  const OrderStatusChips(
      {super.key, required this.selected, required this.onSelected});
  final OrderStatus selected;
  final ValueChanged<OrderStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    const statuses = OrderStatus.values;
    final selColor = Theme.of(context).colorScheme.primary;
    final unSelBg =
        Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 1.2,
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 0.8,
      ),
      child: Row(
        children: [
          for (final s in statuses)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  s.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: SizeConfig.textMultiplier * 1.6,
                    color: s == selected ? Colors.white : Colors.black87,
                  ),
                ),
                selected: s == selected,
                selectedColor: selColor,
                backgroundColor: unSelBg,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: s == selected ? selColor : Colors.white,
                    width: 0.5,
                  ),
                ),
                onSelected: (_) => onSelected(s),
              ),
            ),
        ],
      ),
    );
  }
}
