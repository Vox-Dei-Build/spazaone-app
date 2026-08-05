import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  PermissionHelper._();

  static Future<bool> requestCamera(BuildContext context) async {
    if (kIsWeb) return true;
    return _requestPermission(
      context,
      Permission.camera,
      rationaleTitle: 'Allow Camera Access',
      rationaleMessage:
          'Spaza One needs camera access so you can take photos of your products to share and sell.',
    );
  }

  static Future<bool> requestPhotos(BuildContext context) async {
    if (kIsWeb) return true;
    // Use Permission.photos on both platforms.
    //
    // permission_handler 11.x maps Permission.photos to:
    //   - iOS:           Photos framework (NSPhotoLibraryUsageDescription)
    //   - Android 13+:   READ_MEDIA_IMAGES (granular media permission)
    //   - Android 12-:   READ_EXTERNAL_STORAGE (legacy fallback)
    //
    // Previously this branch asked for Permission.storage on Android,
    // which on API 33+ silently auto-denies because the granular
    // media permissions replaced the broad storage permission. The
    // user saw the gallery flow do nothing without a system prompt.
    const permission = Permission.photos;
    return _requestPermission(
      context,
      permission,
      rationaleTitle: 'Allow Photo Library Access',
      rationaleMessage:
          'Spaza One needs photo library access so you can choose existing product photos to share with customers.',
      treatLimitedAsGranted: true,
    );
  }

  static Future<bool> requestContacts(BuildContext context) async {
    if (kIsWeb) return true;
    return _requestPermission(
      context,
      Permission.contacts,
      rationaleTitle: 'Allow Contacts Access',
      rationaleMessage:
          'Spaza One needs contacts access so you can quickly message customers from your address book.',
    );
  }

  static Future<bool> _requestPermission(
    BuildContext context,
    Permission permission, {
    required String rationaleTitle,
    required String rationaleMessage,
    bool treatLimitedAsGranted = false,
  }) async {
    var status = await permission.status;

    if (_isEffectivelyGranted(status, treatLimitedAsGranted)) {
      return true;
    }

    if (status.isDenied || status.isRestricted) {
      status = await permission.request();
      if (_isEffectivelyGranted(status, treatLimitedAsGranted)) {
        return true;
      }
    }

    return false;
  }

  static bool _isEffectivelyGranted(
    PermissionStatus status,
    bool treatLimitedAsGranted,
  ) {
    if (status.isGranted) return true;
    if (treatLimitedAsGranted && status.isLimited) return true;
    return false;
  }
}
