import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class OrderSkeleton extends StatelessWidget {
  const OrderSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    Widget box({double h = 12, double w = double.infinity}) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: Colors.grey,
            borderRadius: BorderRadius.circular(8),
          ),
        );
    return Shimmer.fromColors(
      baseColor: Colors.black12,
      highlightColor: Colors.black26,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        title: Row(children: [
          box(w: 80),
          const SizedBox(width: 8),
          box(w: 56, h: 20),
        ]),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              box(w: 180),
              const SizedBox(height: 8),
              box(w: 120),
            ],
          ),
        ),
      ),
    );
  }
}
