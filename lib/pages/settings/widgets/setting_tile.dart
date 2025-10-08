import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/utils/text_sanitizer.dart';

class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    this.icon,
    required this.title,
    this.subTitle,
    this.onTap,
    this.trailing,
    this.hideDivider = false,
    this.removeLPadding,
  });

  final IconData? icon;
  final dynamic title;
  final dynamic subTitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool? hideDivider;
  final bool? removeLPadding;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig for responsiveness

    return Column(
      children: [
        ListTile(
          minLeadingWidth: 0.0,
          onTap: onTap,
          contentPadding: EdgeInsets.symmetric(
            vertical: SizeConfig.heightMultiplier * 1,
            horizontal: removeLPadding == true
                ? 0.0
                : SizeConfig.imageSizeMultiplier * 2.5,
          ),
          leading: icon != null
              ? Icon(
                  icon,
                  color: kPrimaryColor,
                  size: SizeConfig.imageSizeMultiplier * 7,
                )
              : const SizedBox.shrink(),
          title: title is String
              ? Text(
                  (title as String).sanitized(),
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: SizeConfig.textMultiplier * 2,
                  ),
                )
              : title,
          subtitle: subTitle is String
              ? Text(
                  (subTitle as String).sanitized(),
                  style: kSubTitleStyle.copyWith(
                      fontSize: SizeConfig.textMultiplier * 1.8),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : subTitle,
          trailing: trailing,
        ),
        hideDivider == true
            ? const SizedBox.shrink()
            : Divider(
                color: kHighLightColor,
                height: SizeConfig.heightMultiplier * 1,
                thickness: 1,
              ),
      ],
    );
  }
}
