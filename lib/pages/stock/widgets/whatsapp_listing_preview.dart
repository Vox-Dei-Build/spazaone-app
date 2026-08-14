import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/utils/currency_util.dart';

/// PAS-UX-XX: Inline "how customers will see this" preview that appears
/// directly under the "List in WhatsApp Store" switch when the merchant
/// turns the toggle ON.
///
/// The preview mimics a WhatsApp incoming chat bubble (white card on the
/// familiar beige chat paper). Showing the rendered listing in place
/// removes the abstraction of the toggle — merchants can immediately see
/// what their product image, name and price look like in the format the
/// customer receives, and that nudges them to upload a photo or tidy the
/// product name before listing it publicly.
///
/// All values are bound to the live form fields via [name], [sellingPrice],
/// [company], [description] and [imageUrl]; the parent rebuilds on every
/// keystroke (the form already calls `viewModel.markUnsavedChanges()` /
/// `setState` on each field change) so the preview updates in real time.
class WhatsappListingPreview extends StatelessWidget {
  final String? name;
  final double? sellingPrice;
  final String? company;
  final String? description;
  final String? imageUrl;
  final File? localImage;
  final String? shopName;

  const WhatsappListingPreview({
    Key? key,
    required this.name,
    required this.sellingPrice,
    required this.company,
    required this.description,
    required this.imageUrl,
    this.localImage,
    this.shopName,
  }) : super(key: key);

  // WhatsApp brand-adjacent colours. We use a chat-paper beige and a
  // plain white incoming bubble so the surface is unmistakably "a
  // WhatsApp chat" without copying any trademarked imagery.
  static const Color _chatPaper = Color(0xFFECE5DD);
  static const Color _bubble = Colors.white;
  static const Color _bubbleShadow = Color(0x1A000000);
  static const Color _accent = Color(0xFF075E54); // WhatsApp dark teal
  static const Color _link = Color(0xFF34B7F1); // WhatsApp link blue
  static const Color _meta = Color(0xFF667781);

  String get _displayName {
    final trimmed = (name ?? '').trim();
    return trimmed.isEmpty ? 'Your product name' : trimmed;
  }

  String get _displayPrice {
    if (sellingPrice == null || sellingPrice! <= 0) {
      return 'Price not set';
    }
    return CurrencyUtil.format(sellingPrice!);
  }

  String? get _displayCompany {
    final trimmed = (company ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get _displayDescription {
    final trimmed = (description ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String get _fromLine {
    final trimmed = (shopName ?? '').trim();
    return trimmed.isEmpty ? 'Your WhatsApp Store' : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final double imageBoxSide = SizeConfig.heightMultiplier * 22;
    final TimeOfDay now = TimeOfDay.now();
    final String timeLabel = '${now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod}:'
        '${now.minute.toString().padLeft(2, '0')} '
        '${now.period == DayPeriod.am ? 'AM' : 'PM'}';

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: SizeConfig.heightMultiplier * 1),
      decoration: BoxDecoration(
        color: _chatPaper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD1C7BD)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 3,
        vertical: SizeConfig.heightMultiplier * 1.5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header strip — clarifies this is a preview, not a real chat.
          Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                size: SizeConfig.imageSizeMultiplier * 4,
                color: _accent,
              ),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
              Expanded(
                child: Text(
                  'Preview — how customers see this on WhatsApp',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.5,
                    fontWeight: FontWeight.w600,
                    color: _accent,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 1.2),
          // The incoming-bubble itself.
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: SizeConfig.screenWidth * 0.78,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: _bubble,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(2),
                    topRight: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _bubbleShadow,
                      blurRadius: 1,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product image (or placeholder).
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(2),
                        topRight: Radius.circular(10),
                      ),
                      child: SizedBox(
                        height: imageBoxSide,
                        width: double.infinity,
                        child: localImage != null
                            ? Image.file(localImage!, fit: BoxFit.cover)
                            : (imageUrl == null || imageUrl!.isEmpty)
                                ? Container(
                                    color: const Color(0xFFEDEDED),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.image_outlined,
                                          size: SizeConfig.imageSizeMultiplier *
                                              10,
                                          color: Colors.grey.shade400,
                                        ),
                                        SizedBox(
                                          height:
                                              SizeConfig.heightMultiplier * 0.5,
                                        ),
                                        Text(
                                          'Add a photo so this stands out',
                                          style: TextStyle(
                                            fontSize:
                                                SizeConfig.textMultiplier * 1.4,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: imageUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) =>
                                        Container(
                                      color: const Color(0xFFEDEDED),
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.grey.shade400,
                                        size:
                                            SizeConfig.imageSizeMultiplier * 10,
                                      ),
                                    ),
                                  ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        SizeConfig.imageSizeMultiplier * 3,
                        SizeConfig.heightMultiplier * 1,
                        SizeConfig.imageSizeMultiplier * 3,
                        SizeConfig.heightMultiplier * 0.8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name (bold, WhatsApp uses *asterisks* — we
                          // render that as actual bold here).
                          Text(
                            _displayName,
                            style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 1.9,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          if (_displayCompany != null) ...[
                            SizedBox(
                              height: SizeConfig.heightMultiplier * 0.2,
                            ),
                            Text(
                              _displayCompany!,
                              style: TextStyle(
                                fontSize: SizeConfig.textMultiplier * 1.5,
                                color: _meta,
                              ),
                            ),
                          ],
                          SizedBox(height: SizeConfig.heightMultiplier * 0.6),
                          Text(
                            _displayPrice,
                            style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 1.8,
                              fontWeight: FontWeight.w600,
                              color:
                                  (sellingPrice == null || sellingPrice! <= 0)
                                      ? Colors.grey
                                      : _accent,
                            ),
                          ),
                          if (_displayDescription != null) ...[
                            SizedBox(height: SizeConfig.heightMultiplier * 0.6),
                            Text(
                              _displayDescription!,
                              style: TextStyle(
                                fontSize: SizeConfig.textMultiplier * 1.55,
                                color: Colors.black87,
                                height: 1.3,
                              ),
                            ),
                          ],
                          SizedBox(height: SizeConfig.heightMultiplier * 0.8),
                          // Order link — what customers actually tap.
                          Row(
                            children: [
                              Icon(
                                Icons.reply_outlined,
                                size: SizeConfig.imageSizeMultiplier * 3.5,
                                color: _link,
                              ),
                              SizedBox(
                                width: SizeConfig.imageSizeMultiplier * 1,
                              ),
                              Expanded(
                                child: Text(
                                  'Reply "Order" to buy from $_fromLine',
                                  style: TextStyle(
                                    fontSize: SizeConfig.textMultiplier * 1.4,
                                    color: _link,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: SizeConfig.heightMultiplier * 0.4),
                          // Timestamp — anchors the chat metaphor.
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              timeLabel,
                              style: TextStyle(
                                fontSize: SizeConfig.textMultiplier * 1.2,
                                color: _meta,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
