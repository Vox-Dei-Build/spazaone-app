import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';
import 'order_avatar.dart';
import 'status_pill.dart';

class OrderTile extends StatelessWidget {
  const OrderTile({
    super.key,
    required this.id,
    required this.status,
    required this.totalText,
    required this.itemsCount,
    required this.dateText,
    required this.onTap,

    // NEW: a general-purpose second pill (collection-focused)
    this.secondPillText = '',
    this.secondPillColor,
  });

  final String id;
  final OrderStatus status;
  final String totalText;
  final int? itemsCount;
  final String dateText;
  final VoidCallback onTap;

  // NEW
  final String secondPillText;
  final Color? secondPillColor;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 3,
              vertical: SizeConfig.heightMultiplier * 1.2,
            ),
            visualDensity: const VisualDensity(horizontal: -2),
            leading: OrderAvatar(color: status.color(context)),
            title: _buildTitle(context),
            subtitle: _buildSubtitle(context),
            trailing: const Icon(Icons.chevron_right),
          ),
          const Divider(color: kHighLightColor, height: 5),
        ],
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    final showSecond = secondPillText.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // <— was spaceEvenly
        children: [
          // LEFT: id + pills (wrap if tight)
          Expanded(
            child: Wrap(
              spacing: SizeConfig.imageSizeMultiplier * 1.5,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Order id
                ConstrainedBox(
                  constraints: const BoxConstraints(
                      minWidth: 0, maxWidth: double.infinity),
                  child: Text(
                    '#$id',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: SizeConfig.textMultiplier * 1.8,
                    ),
                  ),
                ),

                // Primary: resolved order status
                StatusPill(
                  text: status.label,
                  color: status.color(context),
                ),

                // Second: collection pill (only when present)
                if (showSecond)
                  StatusPill(
                    text: secondPillText,
                    color: secondPillColor ??
                        Theme.of(context).colorScheme.outline,
                  ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // RIGHT: total (scales down instead of overflowing)
          Flexible(
            flex: 0,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                totalText,
                style: TextStyle(
                  color: kPrimaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: SizeConfig.textMultiplier * 1.8,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitle(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                color: status == OrderStatus.paid ? kPrimaryColor : Colors.red,
                fontWeight: FontWeight.w500,
                fontSize: SizeConfig.textMultiplier * 1.5,
              ),
              children: [
                TextSpan(text: totalText),
                TextSpan(
                  text: ' · ${itemsCount ?? 0} items · ',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                TextSpan(
                  text: dateText,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
