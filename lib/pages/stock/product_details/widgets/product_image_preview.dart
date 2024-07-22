import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ProductImagePreview extends StatelessWidget {
  final String? imageUrl;

  const ProductImagePreview({Key? key, this.imageUrl}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: SizedBox(
          height: 100,
          width: 100,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Container(
              color: Colors.white,
              child: Container(
                color: Colors.green.withOpacity(0.1),
                child: (imageUrl == null)
                    ? Center(
                        child: Icon(
                          Icons.image,
                          color: Colors.green.withOpacity(0.5),
                        ),
                      )
                    : CachedNetworkImage(
                        fit: BoxFit.cover,
                        imageUrl: imageUrl!,
                        errorWidget: (context, url, error) => Icon(
                          Icons.image,
                          color: Colors.green.withOpacity(0.5),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
