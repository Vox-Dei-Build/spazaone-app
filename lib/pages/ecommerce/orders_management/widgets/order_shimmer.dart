import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:shimmer/shimmer.dart';

class OrderStatusChipsSkeleton extends StatelessWidget {
  const OrderStatusChipsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget chip(double w) => Container(
          height: 34,
          width: w,
          decoration: BoxDecoration(
            color: Colors.grey,
            borderRadius: BorderRadius.circular(999),
          ),
        );

    return Shimmer.fromColors(
      baseColor: Colors.black12,
      highlightColor: Colors.black26,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 3,
          vertical: SizeConfig.heightMultiplier * 0.8,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip(64),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
              chip(72),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
              chip(84),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
              chip(92),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
              chip(80),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
              chip(96),
            ],
          ),
        ),
      ),
    );
  }
}

class OrdersSummaryBarSkeleton extends StatelessWidget {
  const OrdersSummaryBarSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bar({double h = 16, double w = 80, double r = 8}) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(r),
          ),
        );

    return Shimmer.fromColors(
      baseColor: Colors.black12,
      highlightColor: Colors.black26,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          SizeConfig.imageSizeMultiplier * 3,
          SizeConfig.heightMultiplier * 1.2,
          SizeConfig.imageSizeMultiplier * 3,
          SizeConfig.heightMultiplier * 1.0,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: SizeConfig.heightMultiplier * 1.0,
            horizontal: SizeConfig.imageSizeMultiplier * 2.2,
          ),
          decoration: BoxDecoration(
            color: Colors.grey,
            borderRadius:
                BorderRadius.circular(SizeConfig.imageSizeMultiplier * 2),
          ),
          child: Row(
            children: [
              // left group (count + label)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(h: 14, w: 90, r: 6),
                    SizedBox(height: SizeConfig.heightMultiplier * 0.6),
                    bar(h: 20, w: 120, r: 6),
                  ],
                ),
              ),
              // right group (total + range)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  bar(h: 14, w: 80, r: 6),
                  SizedBox(height: SizeConfig.heightMultiplier * 0.6),
                  bar(h: 20, w: 140, r: 6),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
