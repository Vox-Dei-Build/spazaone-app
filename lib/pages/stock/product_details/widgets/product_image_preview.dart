import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

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
            borderRadius: BorderRadius.circular(SpazaRadius.control),
            child: Container(
              color: Colors.white,
              child: Container(
                color: SpazaColors.subtle,
                child: (imageUrl == null)
                    ? const Center(
                        child: Icon(
                          Icons.image,
                          color: SpazaColors.muted,
                        ),
                      )
                    : CachedNetworkImage(
                        fit: BoxFit.cover,
                        imageUrl: imageUrl!,
                        errorWidget: (context, url, error) => const Icon(
                          Icons.image,
                          color: SpazaColors.muted,
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
