import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/shared/widgets/profile_status_icon.dart';
import 'package:pasella/shared/widgets/showProfileImageDialog.dart';

class ProfileImageWidget extends StatelessWidget {
  final String? imageUrl;
  final File? imageFile;
  final String initials;
  final double radius;
  final VoidCallback? onTap;

  const ProfileImageWidget({
    Key? key,
    this.imageUrl,
    this.imageFile,
    required this.initials,
    required this.radius,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: CircleAvatar(
        radius: radius,
        backgroundImage: imageFile != null
            ? FileImage(imageFile!)
            : (imageUrl != null
                ? CachedNetworkImageProvider(imageUrl!)
                    as ImageProvider<Object>?
                : null),
        backgroundColor: (imageUrl == null && imageFile == null)
            ? Color(kTertiaryColor.value)
            : null,
        child: (imageFile == null && imageUrl == null)
            ? Text(
                initials.isNotEmpty ? initials[0] : '',
                style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 2.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              )
            : null,
      ),
    );
  }
}

Widget profilePicture(BuildContext context, String name, String? imageUrl,
    String? number, bool? isNPA,
    {bool displayIcons = true, final double? radius, File? profileImage}) {
  var initials = name.isNotEmpty ? name[0] : '';
  return Stack(
    children: [
      ProfileImageWidget(
        imageUrl: imageUrl,
        imageFile: profileImage,
        initials: initials,
        radius: radius ?? SizeConfig.heightMultiplier * 3,
        onTap: () => showProfileImageDialog(context, imageUrl, null, initials),
      ),
      displayIcons
          ? Positioned(
              left: 0,
              bottom: 0,
              child: ProfileStatusIcon(
                isEnabled: number != null && number.isNotEmpty,
                enabledIcon: Icons.phone_enabled,
                disabledIcon: Icons.phone_disabled,
              ),
            )
          : Container(),
      displayIcons
          ? Positioned(
              right: 0,
              bottom: 0,
              child: ProfileStatusIcon(
                isEnabled: isNPA == true,
                enabledIcon: Icons.report,
                disabledIcon: Icons.verified_user,
                enabledColor: Colors.red,
                disabledColor: Colors.green,
              ),
            )
          : Container(),
    ],
  );
}
