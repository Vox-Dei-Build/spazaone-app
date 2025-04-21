import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/settings/settings.dart';
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
      padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 1,
          vertical: SizeConfig.heightMultiplier * 0),
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
          const Spacer(),
          if (onSearchTap != null)
            Expanded(
              child: IconButton(
                icon: Icon(Icons.search,
                    color: Colors.black,
                    size: SizeConfig.imageSizeMultiplier * 5),
                onPressed: onSearchTap,
                alignment: Alignment.centerRight,
              ),
            )
          else
            const Spacer(),
          const Spacer(),
          if (actionWidget != null) actionWidget!,
          const Spacer(),
          Expanded(
            child: IconButton(
              icon: Icon(Icons.settings_outlined,
                  color: Colors.black,
                  size: SizeConfig.imageSizeMultiplier * 5),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SettingsPage(),
                  ),
                );
              },
              alignment: Alignment.centerRight,
            ),
          ),
          const Spacer(),
          const ConnectivityIndicator(),
        ],
      ),
    );
  }
}
