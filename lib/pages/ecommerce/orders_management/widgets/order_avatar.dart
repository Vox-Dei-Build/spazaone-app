import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

class OrderAvatar extends StatelessWidget {
  const OrderAvatar({super.key, required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: SizeConfig.imageSizeMultiplier * 4.5,
      backgroundColor: color.withOpacity(0.12),
      child: Icon(Icons.shopping_bag_rounded, color: color),
    );
  }
}
