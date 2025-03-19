import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasella/config/size_config.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomAppBar({
    super.key,
    required this.title,
    this.trailing,
    this.onBack = true,
    this.leading,
  });

  final String title;
  final Widget? trailing;
  final bool onBack;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return AppBar(
      leadingWidth: 30,
      leading: onBack
          ? IconButton(
              onPressed: () {
                FocusScope.of(context).unfocus();
                SystemChannels.textInput.invokeMethod('TextInput.hide');
                Navigator.pop(context);
              },
              icon: Icon(
                Icons.arrow_back_ios,
                size:
                    SizeConfig.imageSizeMultiplier * 6, // Responsive icon size
              ),
            )
          : leading != null
              ? leading
              : null, // Provide an empty space or null if onBack is false or there is no leading icon
      title: Text(
        title,
        style: TextStyle(
          fontSize: SizeConfig.textMultiplier * 2, // Responsive font size
          fontWeight: FontWeight.w900,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      centerTitle: true,
      actions: <Widget>[
        if (trailing != null) trailing! else Container(),
      ],
      // Customize your AppBar further if needed
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight);
}
