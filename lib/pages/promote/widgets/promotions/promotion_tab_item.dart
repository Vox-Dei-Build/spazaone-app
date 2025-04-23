import 'package:flutter/material.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';

class TabItem {
  final String title;
  final Widget content;
  final String fabLabel;
  final IconData fabIcon;
  final Future<void> Function(BuildContext, PromotionsViewModel) onTap;

  const TabItem({
    required this.title,
    required this.content,
    required this.fabLabel,
    required this.fabIcon,
    required this.onTap,
  });
}
