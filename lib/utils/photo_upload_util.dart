import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:pasella/utils/permission_helper.dart';

class PhotoUploadUtil {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<File?> pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
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
      keepExif: true,
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

  Future<bool?> showCameraOrGalleryPicker(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select an option'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Camera')),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Gallery')),
          ],
        ),
      ),
    );
  }

  Future<void> handleImagePick(
      BuildContext context, Function(File?) onImagePicked) async {
    final isCamera = await showCameraOrGalleryPicker(context);
    if (isCamera == null) return;

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
    final bool granted;
    if (isCamera) {
      granted = await PermissionHelper.requestCamera(context);
    } else if (Platform.isAndroid) {
      granted = true; // Photo Picker handles gallery auth implicitly.
    } else {
      granted = await PermissionHelper.requestPhotos(context);
    }

    if (!granted) {
      onImagePicked(null);
      return;
    }

    final source = isCamera ? ImageSource.camera : ImageSource.gallery;
    final picked = await pickImage(source);
    if (picked == null) {
      onImagePicked(null);
      return;
    }

    final compressed = await compressImage(picked);
    onImagePicked(compressed);
  }
}
