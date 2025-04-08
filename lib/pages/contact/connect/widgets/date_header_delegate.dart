import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

class DateHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String date;

  DateHeaderDelegate({required this.date});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.transparent, // match your chat background color
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
        ),
        child: Text(
          date,
          style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.8,
              fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  @override
  double get maxExtent => 40;

  @override
  double get minExtent => 40;

  @override
  bool shouldRebuild(DateHeaderDelegate oldDelegate) =>
      date != oldDelegate.date;
}
