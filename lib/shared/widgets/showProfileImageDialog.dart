import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';

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
                            // PAS-PROFILE-IMG-403: stale Firebase Storage
                            // URLs return 403; fall back to the initials
                            // avatar instead of a generic error glyph so
                            // the dialog still feels intentional and the
                            // failure never escalates to a fatal error.
                            errorWidget: (context, url, error) =>
                                _initialsFallback(initials),
                          )
                        : _initialsFallback(initials)),
                SizedBox(height: SizeConfig.heightMultiplier * 3),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Close',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: SizeConfig.textMultiplier * 2)),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

CircleAvatar _initialsFallback(String initials) {
  return CircleAvatar(
    radius: SizeConfig.imageSizeMultiplier * 15,
    backgroundColor: Color(kTertiaryColor.value),
    child: Text(
      initials,
      style: TextStyle(
        color: Colors.white,
        fontSize: SizeConfig.textMultiplier * 2,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
