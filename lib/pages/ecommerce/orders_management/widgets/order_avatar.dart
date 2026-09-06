import 'package:flutter/material.dart';

class OrderAvatar extends StatelessWidget {
  const OrderAvatar({super.key, required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(Icons.shopping_bag_outlined, size: 22, color: color),
    );
  }
}
