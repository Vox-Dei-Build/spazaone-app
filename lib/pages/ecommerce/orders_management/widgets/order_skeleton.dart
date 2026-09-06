import 'package:flutter/material.dart';
import 'package:pasella/shared/widgets/spaza_shimmer.dart';

class OrderSkeleton extends StatelessWidget {
  const OrderSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return const SpazaShimmer(
      semanticsLabel: 'Loading order',
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        title: Row(children: [
          SpazaSkeletonBox(width: 80, height: 12),
          SizedBox(width: 8),
          SpazaSkeletonBox(width: 56, height: 20),
        ]),
        subtitle: Padding(
          padding: EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SpazaSkeletonBox(width: 180, height: 12),
              SizedBox(height: 8),
              SpazaSkeletonBox(width: 120, height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
