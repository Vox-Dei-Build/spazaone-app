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
      child: _buildAvatar(),
    );
  }

  Widget _buildAvatar() {
    // Local file image: render directly. FileImage failures are extremely
    // rare and not the source of the production 403 crashes.
    if (imageFile != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(imageFile!),
      );
    }

    // No image at all -> initials placeholder.
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _initialsAvatar();
    }

    // PAS-PROFILE-IMG-403: Remote image. We deliberately use
    // [CachedNetworkImage] (not [CachedNetworkImageProvider] inside
    // [CircleAvatar.backgroundImage]) so we can attach an [errorWidget]
    // and gracefully fall back when Firebase Storage returns 403/404 on
    // stale signed URLs. Using the provider directly bubbles the load
    // failure up through the image stream and is reported as a fatal
    // FlutterError by Crashlytics.
    final double diameter = radius * 2;
    return ClipOval(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          fit: BoxFit.cover,
          width: diameter,
          height: diameter,
          // Show the initials placeholder while loading so the avatar
          // surface is never blank.
          placeholder: (context, url) => _initialsAvatar(),
          errorWidget: (context, url, error) => _initialsAvatar(),
        ),
      ),
    );
  }

  Widget _initialsAvatar() {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color(kTertiaryColor.value),
      child: Text(
        // PAS-UI-UTF16: Use [_firstGrapheme] instead of indexing with
        // `String[0]` — the latter returns a single UTF-16 code unit and
        // will split a surrogate pair (e.g. when the customer name starts
        // with an emoji), producing a malformed string that crashes
        // [TextPainter.layout] with "string is not well-formed UTF-16".
        _firstGrapheme(initials),
        style: TextStyle(
          fontSize: SizeConfig.textMultiplier * 2,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Returns the first user-perceived character of [value] without splitting
/// a UTF-16 surrogate pair. Falls back to an empty string when [value] is
/// empty. We intentionally take the first *rune* rather than `value[0]` so
/// that names starting with astral-plane characters (emoji, many CJK
/// extensions, etc.) do not produce a lone high-surrogate that would crash
/// the text engine.
String _firstGrapheme(String value) {
  if (value.isEmpty) return '';
  final runes = value.runes;
  if (runes.isEmpty) return '';
  return String.fromCharCode(runes.first);
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
String _phoneTooltip(bool hasNumber) => hasNumber
    ? 'Phone number on file — you can send a payment request.'
    : 'No phone number — add one to request payment.';

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
  // PAS-UI-UTF16: see [_firstGrapheme] — never index a String with `[0]`
  // when the value comes from user input or server data, otherwise an
  // emoji at the start of the name will be split mid-surrogate and crash
  // the text engine.
  var initials = _firstGrapheme(name);
  final bool hasNumber = number != null && number.isNotEmpty;
  final double avatarRadius = radius ?? SizeConfig.heightMultiplier * 3;
  // Only show the explicit "No phone" text pill on larger avatar
  // surfaces. Dense list tiles do not have enough room, so icon +
  // tooltip is cleaner and avoids clipping.
  final bool showMissingPhoneLabel =
      displayIcons && !hasNumber && avatarRadius >= 28;
  final double extraWidthForMissingPhone =
      showMissingPhoneLabel ? SizeConfig.imageSizeMultiplier * 10 : 0;

  return SizedBox(
    width: (avatarRadius * 2) + extraWidthForMissingPhone,
    height: avatarRadius * 2,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        ProfileImageWidget(
          imageUrl: imageUrl,
          imageFile: profileImage,
          initials: initials,
          radius: avatarRadius,
          onTap: () =>
              showProfileImageDialog(context, imageUrl, null, initials),
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
                  // PAS-AUTH-02: show the explicit missing-phone label only
                  // where the avatar surface is large enough to hold it.
                  // Compact customer tiles fall back to icon + tooltip.
                  disabledLabel: showMissingPhoneLabel ? 'No phone' : null,
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
    ),
  );
}
