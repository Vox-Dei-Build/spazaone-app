import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

void showProfileImageDialog(
    BuildContext context, String? imageUrl, File? imageFile, String initials) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 4),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                imageFile != null
                    ? Image.file(imageFile)
                    : (imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            placeholder: (context, url) =>
                                const CircularProgressIndicator(),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.error),
                          )
                        : CircleAvatar(
                            radius: SizeConfig.imageSizeMultiplier * 15,
                            backgroundColor: Colors.grey[300],
                            child: Icon(Icons.person,
                                size: SizeConfig.imageSizeMultiplier * 15,
                                color: Colors.grey[600]),
                          )),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
