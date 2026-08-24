import 'dart:async';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasella/utils/permission_helper.dart';

export 'package:pasella/utils/permission_helper.dart'
    show PhotoPermissionPurpose;

enum _PhotoRecoveryAction { cancel, gallery, settings }

class PhotoUploadUtil {
  PhotoUploadUtil({ImagePicker? picker, FirebaseStorage? storage})
      : _picker = picker ?? ImagePicker(),
        _providedStorage = storage;

  final ImagePicker _picker;
  final FirebaseStorage? _providedStorage;
  FirebaseStorage get _storage => _providedStorage ?? FirebaseStorage.instance;

  @visibleForTesting
  static const preserveExifOnCompression = false;

  Future<File?> pickImage(ImageSource source) async {
    if (Platform.isAndroid) {
      final lost = await _picker.retrieveLostData();
      if (lost.exception != null) throw lost.exception!;
      final recovered = lost.files?.firstOrNull;
      if (recovered != null) return File(recovered.path);
    }
    final picked = await _picker.pickImage(source: source);
    return picked != null ? File(picked.path) : null;
  }

  Future<File?> compressImage(File file) async {
    final ext = path.extension(file.path).toLowerCase();
    final dir = await getTemporaryDirectory();

    late CompressFormat format;
    late String targetExt;
    if (ext == '.jpg' || ext == '.jpeg') {
      format = CompressFormat.jpeg;
      targetExt = '.jpg';
    } else if (ext == '.png') {
      format = CompressFormat.png;
      targetExt = '.png';
    } else if (ext == '.heic' || ext == '.heif') {
      // Convert HEIC/HEIF (common from iOS camera) to JPEG for compatibility
      format = CompressFormat.jpeg;
      targetExt = '.jpg';
    } else {
      debugPrint('Unsupported image format: $ext');
      return null;
    }

    final fileName =
        'compressed_${DateTime.now().millisecondsSinceEpoch}$targetExt';
    final targetPath = path.join(dir.path, fileName);

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 75,
      format: format,
      keepExif: preserveExifOnCompression,
    );
    return result != null ? File(result.path) : null;
  }

  // NEW: infer content type from extension
  String _inferContentType(String uploadPath) {
    final ext = path.extension(uploadPath).toLowerCase();
    if (ext == '.png') return 'image/png';
    return 'image/jpeg'; // default
  }

  /// Upload with correct Content-Type (critical for WhatsApp)
  Future<String?> uploadImage(File imageFile, String uploadPath) async {
    try {
      // Ensure path has a proper extension (default .jpg)
      var fixedPath = uploadPath;
      final ext = path.extension(uploadPath).toLowerCase();
      if (ext != '.jpg' && ext != '.jpeg' && ext != '.png') {
        fixedPath = '$uploadPath.jpg';
      }

      final contentType = _inferContentType(fixedPath);
      final ref = _storage.ref(fixedPath);

      final task = await ref.putFile(
        imageFile,
        SettableMetadata(
          contentType: contentType,
          cacheControl: 'public, max-age=86400',
        ),
      );

      return await task.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Failed to upload image: $e');
      return null;
    }
  }

  Future<ImageSource?> showCameraOrGalleryPicker(BuildContext context) async {
    return showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a photo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
                onPressed: () => Navigator.pop(context, ImageSource.camera),
                child: const Text('Camera')),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, ImageSource.gallery),
                child: const Text('Gallery')),
          ],
        ),
      ),
    );
  }

  Future<void> handleImagePick(
    BuildContext context,
    FutureOr<void> Function(File?) onImagePicked, {
    PhotoPermissionPurpose purpose = PhotoPermissionPurpose.product,
  }) async {
    var source = await showCameraOrGalleryPicker(context);
    if (source == null) return;

    // Permission strategy by source + platform:
    //
    //   Camera (any platform)
    //     → request Permission.camera (CAMERA on Android,
    //       NSCameraUsageDescription on iOS).
    //
    //   Gallery on Android
    //     → DO NOT request Permission.photos. image_picker on Android
    //       13+ uses the system Photo Picker which deliberately needs
    //       no runtime permission, and on Android 12 and below the
    //       legacy READ_EXTERNAL_STORAGE permission is granted at
    //       install time via the manifest declaration (no runtime
    //       prompt either). Requesting Permission.photos here would
    //       resolve to READ_MEDIA_IMAGES on Android 13+, which we
    //       intentionally don't declare in the manifest (see comment
    //       there about Google Play's Photo and Video Permissions
    //       policy). With the permission undeclared, the request
    //       auto-denies and the picker would silently abort —
    //       reproducing the original Android-13+ gallery bug from a
    //       different angle.
    //
    //   Gallery on iOS
    //     → request Permission.photos. Maps to the Photos framework
    //       and requires NSPhotoLibraryUsageDescription in Info.plist.
    //       iOS Photo Library permission cannot be skipped.
    PermissionRequestOutcome permission;
    if (source == ImageSource.camera) {
      permission = await PermissionHelper.requestCameraAccess(
        context,
        purpose: purpose,
      );
    } else if (Platform.isAndroid) {
      permission = PermissionRequestOutcome.granted;
    } else {
      permission = await PermissionHelper.requestPhotoLibraryAccess(
        context,
        purpose: purpose,
      );
    }

    if (permission != PermissionRequestOutcome.granted) {
      if (!context.mounted) {
        await onImagePicked(null);
        return;
      }
      final recovery = await _showPermissionRecovery(
        context,
        source: source,
        outcome: permission,
      );
      if (recovery == _PhotoRecoveryAction.settings) {
        await PermissionHelper.openSettings();
        await onImagePicked(null);
        return;
      }
      if (recovery != _PhotoRecoveryAction.gallery) {
        await onImagePicked(null);
        return;
      }
      source = ImageSource.gallery;
    }

    File? picked;
    try {
      picked = await pickImage(source);
    } on PlatformException catch (error) {
      if (!context.mounted) {
        await onImagePicked(null);
        return;
      }
      final recovery = await _showPickerFailure(
        context,
        source: source,
        code: error.code,
      );
      if (source == ImageSource.camera &&
          recovery == _PhotoRecoveryAction.gallery) {
        try {
          picked = await pickImage(ImageSource.gallery);
        } on PlatformException catch (galleryError) {
          if (context.mounted) {
            _showGalleryError(context, galleryError.code);
          }
        }
      }
    } catch (_) {
      if (context.mounted) {
        await _showPickerFailure(
          context,
          source: source,
          code: 'unavailable',
        );
      }
    }
    if (picked == null) {
      await onImagePicked(null);
      return;
    }

    try {
      final compressed = await compressImage(picked);
      if (compressed == null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That image format could not be prepared. Try another photo.',
            ),
          ),
        );
      }
      await onImagePicked(compressed);
    } on PlatformException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The photo could not be prepared. Try Gallery or another image.',
            ),
          ),
        );
      }
      await onImagePicked(null);
    }
  }

  @visibleForTesting
  static String pickerFailureMessage(ImageSource source, String code) {
    if (source == ImageSource.camera) {
      return 'SpazaOne could not open the camera. Check that a camera app is available, or use Gallery instead.';
    }
    return 'SpazaOne could not open Gallery. Check photo access and try again.';
  }

  Future<_PhotoRecoveryAction?> _showPermissionRecovery(
    BuildContext context, {
    required ImageSource source,
    required PermissionRequestOutcome outcome,
  }) {
    final permanentlyDenied =
        outcome == PermissionRequestOutcome.permanentlyDenied ||
            outcome == PermissionRequestOutcome.restricted;
    final isCamera = source == ImageSource.camera;
    return showDialog<_PhotoRecoveryAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isCamera ? 'Camera access needed' : 'Photo access needed'),
        content: Text(
          permanentlyDenied
              ? '${isCamera ? 'Camera' : 'Photo library'} access is turned off for SpazaOne. Open app settings to allow it, or use Gallery when available.'
              : '${isCamera ? 'Camera' : 'Photo library'} permission was not allowed. You can try again later or use Gallery instead.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _PhotoRecoveryAction.cancel),
            child: const Text('Cancel'),
          ),
          if (isCamera)
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _PhotoRecoveryAction.gallery),
              child: const Text('Use Gallery'),
            ),
          if (permanentlyDenied)
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _PhotoRecoveryAction.settings),
              child: const Text('Open settings'),
            ),
        ],
      ),
    );
  }

  Future<_PhotoRecoveryAction?> _showPickerFailure(
    BuildContext context, {
    required ImageSource source,
    required String code,
  }) {
    return showDialog<_PhotoRecoveryAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(source == ImageSource.camera
            ? 'Camera unavailable'
            : 'Gallery unavailable'),
        content: Text(pickerFailureMessage(source, code)),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _PhotoRecoveryAction.cancel),
            child: const Text('Close'),
          ),
          if (source == ImageSource.camera)
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _PhotoRecoveryAction.gallery),
              child: const Text('Use Gallery'),
            ),
        ],
      ),
    );
  }

  void _showGalleryError(BuildContext context, String code) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(pickerFailureMessage(ImageSource.gallery, code))),
    );
  }
}
