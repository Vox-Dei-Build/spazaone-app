import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class PhotoUploadUtil {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<File?> pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      return File(pickedFile.path);
    }
    return null;
  }

  Future<File?> compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final fileName =
        'compressed_${path.basename(file.path)}'; // Ensure unique target path
    final targetPath = path.join(dir.absolute.path, fileName);

    var result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 20,
    );

    return result != null ? File(result.path) : null;
  }

  Future<String?> uploadImage(File imageFile, String uploadPath) async {
    try {
      final file = await _storage.ref(uploadPath).putFile(imageFile);
      return await file.ref.getDownloadURL();
    } catch (e) {
      print('Failed to upload image: $e');
      return null;
    }
  }

  Future<bool?> showCameraOrGalleryPicker(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select an option'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text("Camera"),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text("Gallery"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> handleImagePick(
      BuildContext context, Function(File?) onImagePicked) async {
    bool? isCamera = await showCameraOrGalleryPicker(context);
    if (isCamera != null) {
      ImageSource source = isCamera ? ImageSource.camera : ImageSource.gallery;
      File? pickedImage = await pickImage(source);

      if (pickedImage != null) {
        File? compressedImage = await compressImage(pickedImage);
        onImagePicked(compressedImage);
      } else {
        onImagePicked(null);
      }
    }
  }
}
