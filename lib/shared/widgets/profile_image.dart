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
        backgroundImage:
            imageFile != null
                ? FileImage(imageFile!)
                : (imageUrl != null
                    ? CachedNetworkImageProvider(imageUrl!)
                        as ImageProvider<Object>?
                    : null),
        backgroundColor:
            (imageUrl == null && imageFile == null)
                ? Color(kTertiaryColor.value)
                : null,
        child:
            (imageFile == null && imageUrl == null)
                ? Text(
                  initials.isNotEmpty ? initials[0] : '',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                )
                : null,
      ),
    );
  }
}

/// PAS-UI-01: the legacy red NPA dot has been retired in favour of
/// [PaymentStatusPill] on every surface that has room for a label
/// (customer list, profile header, transaction tiles, reports).
/// [showNPAIndicator] now defaults to `false` so the dot stops
/// rendering across the app; the parameter is kept for back-compat
/// only — no production surface should pass `true`.
///
/// The phone icon keeps a tooltip because it surfaces a non-obvious
/// distinction (number on file vs not) and is sometimes the only thing
/// telling a merchant they can't message a client.
String _phoneTooltip(bool hasNumber) =>
    hasNumber
        ? 'Phone number on file — you can send WhatsApp or SMS reminders.'
        : 'No phone number — add one to send payment reminders.';

Widget profilePicture(
  BuildContext context,
  String name,
  String? imageUrl,
  String? number,
  bool? isNPA, {
  bool displayIcons = true,
  final double? radius,
  File? profileImage,
  double? balance,
  bool showNPAIndicator = false,
}) {
  var initials = name.isNotEmpty ? name[0] : '';
  final bool hasNumber = number != null && number.isNotEmpty;
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
              isEnabled: hasNumber,
              enabledIcon: Icons.phone_enabled,
              disabledIcon: Icons.phone_disabled,
              enabledTooltip: _phoneTooltip(true),
              disabledTooltip: _phoneTooltip(false),
              // PAS-AUTH-02: the affirmative "phone on file" state is the
              // common case so we leave it icon-only to avoid clutter on
              // every avatar in the ledger list. The *missing* state is
              // the actionable signal — merchants can't message a client
              // without a number — so we render an explicit "No phone"
              // pill instead of relying on a tooltip nobody taps.
              disabledLabel: 'No phone',
            ),
          )
          : Container(),
      displayIcons && showNPAIndicator
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
