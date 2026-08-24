import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

enum PhotoPermissionPurpose { product, customer, stockInvoice }

enum PermissionRequestOutcome {
  granted,
  denied,
  permanentlyDenied,
  restricted,
}

class PermissionHelper {
  PermissionHelper._();

  static String cameraRationaleMessage(PhotoPermissionPurpose purpose) {
    return switch (purpose) {
      PhotoPermissionPurpose.product =>
        'SpazaOne needs camera access so you can take a product photo.',
      PhotoPermissionPurpose.customer =>
        'SpazaOne needs camera access so you can take a customer profile photo.',
      PhotoPermissionPurpose.stockInvoice =>
        'SpazaOne needs camera access so you can photograph a stock invoice.',
    };
  }

  static String photoLibraryRationaleMessage(PhotoPermissionPurpose purpose) {
    return switch (purpose) {
      PhotoPermissionPurpose.product =>
        'SpazaOne needs photo library access so you can choose a product photo.',
      PhotoPermissionPurpose.customer =>
        'SpazaOne needs photo library access so you can choose a customer profile photo.',
      PhotoPermissionPurpose.stockInvoice =>
        'SpazaOne needs photo library access so you can choose a stock invoice image.',
    };
  }

  static Future<PermissionRequestOutcome> requestCameraAccess(
    BuildContext context, {
    PhotoPermissionPurpose purpose = PhotoPermissionPurpose.product,
  }) async {
    if (kIsWeb) return PermissionRequestOutcome.granted;
    return _requestPermissionOutcome(
      context,
      Permission.camera,
      rationaleTitle: 'Allow Camera Access',
      rationaleMessage: cameraRationaleMessage(purpose),
    );
  }

  static Future<PermissionRequestOutcome> requestPhotoLibraryAccess(
    BuildContext context, {
    PhotoPermissionPurpose purpose = PhotoPermissionPurpose.product,
  }) async {
    if (kIsWeb) return PermissionRequestOutcome.granted;
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
    return _requestPermissionOutcome(
      context,
      permission,
      rationaleTitle: 'Allow Photo Library Access',
      rationaleMessage: photoLibraryRationaleMessage(purpose),
      treatLimitedAsGranted: true,
    );
  }

  static Future<bool> requestCamera(BuildContext context) async =>
      await requestCameraAccess(context) == PermissionRequestOutcome.granted;

  static Future<bool> requestPhotos(BuildContext context) async =>
      await requestPhotoLibraryAccess(context) ==
      PermissionRequestOutcome.granted;

  static Future<bool> requestContacts(BuildContext context) async {
    if (kIsWeb) return true;
    return (await _requestPermissionOutcome(
          context,
          Permission.contacts,
          rationaleTitle: 'Allow Contacts Access',
          rationaleMessage:
              'Spaza One needs contacts access so you can quickly message customers from your address book.',
        )) ==
        PermissionRequestOutcome.granted;
  }

  static Future<PermissionRequestOutcome> _requestPermissionOutcome(
    BuildContext context,
    Permission permission, {
    required String rationaleTitle,
    required String rationaleMessage,
    bool treatLimitedAsGranted = false,
  }) async {
    var status = await permission.status;

    if (_isEffectivelyGranted(status, treatLimitedAsGranted)) {
      return PermissionRequestOutcome.granted;
    }

    if (status.isDenied || status.isRestricted) {
      if (!context.mounted) return outcomeForStatus(status);
      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(rationaleTitle),
          content: Text(rationaleMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (shouldRequest != true) return outcomeForStatus(status);
      status = await permission.request();
      if (_isEffectivelyGranted(status, treatLimitedAsGranted)) {
        return PermissionRequestOutcome.granted;
      }
    }

    return outcomeForStatus(status);
  }

  @visibleForTesting
  static PermissionRequestOutcome outcomeForStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return PermissionRequestOutcome.granted;
    }
    if (status.isPermanentlyDenied) {
      return PermissionRequestOutcome.permanentlyDenied;
    }
    if (status.isRestricted) return PermissionRequestOutcome.restricted;
    return PermissionRequestOutcome.denied;
  }

  static Future<bool> openSettings() => openAppSettings();

  static bool _isEffectivelyGranted(
    PermissionStatus status,
    bool treatLimitedAsGranted,
  ) {
    if (status.isGranted) return true;
    if (treatLimitedAsGranted && status.isLimited) return true;
    return false;
  }
}
