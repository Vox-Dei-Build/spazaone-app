import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/connectivity_widget.dart';

class PageHeader extends StatelessWidget {
  final VoidCallback? onSearchTap;
  final Widget? actionWidget;

  const PageHeader({
    Key? key,
    this.onSearchTap,
    this.actionWidget,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: SizeConfig.imageSizeMultiplier * 2),
      child: Row(
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            color: Colors.orangeAccent,
            size: SizeConfig.imageSizeMultiplier * 7,
          ),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 1.3),
          Text(
            'Pasella',
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 4,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
          if (onSearchTap != null)
            Expanded(
              child: IconButton(
                icon: Icon(Icons.search,
                    color: Colors.black,
                    size: SizeConfig.imageSizeMultiplier * 7),
                onPressed: onSearchTap,
                alignment: Alignment.centerRight,
              ),
            )
          else
            Spacer(),
          if (actionWidget != null) actionWidget!,
          SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
          ConnectivityIndicator(),
        ],
      ),
    );
  }
}
