import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/force_boilerplate.dart';
import 'package:pasella/utils/photo_upload_util.dart';
import 'package:pasella/utils/sms_pricing_util.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:path/path.dart' as path;

class ContentStep extends StatelessWidget {
  final bool includeWhatsApp;
  final bool includeSMS;
  final TextEditingController whatsappContentController;
  final TextEditingController smsContentController;
  final TextEditingController mediaUrlController;
  final PhotoUploadUtil photoUtil;
  final bool uploadingImage;
  final Function(bool) onImageUploadingChanged;
  final double? whatsappPrice;
  final double? smsPricePerSegment;
  final int smsSegments;
  /// Encoding + offending-character info for the current SMS body. Drives
  /// the inline warning that explains *why* a body went UCS-2 (e.g.
  /// "Contains an en-dash (–) — message costs 2 segments. Replace with -
  /// to drop to 1 segment.").
  final SmsEncodingInfo smsEncodingInfo;
  final Function(String) onSmsPricingUpdate;
  final String shopName;

  const ContentStep({
    super.key,
    required this.includeWhatsApp,
    required this.includeSMS,
    required this.whatsappContentController,
    required this.smsContentController,
    required this.mediaUrlController,
    required this.photoUtil,
    required this.uploadingImage,
    required this.onImageUploadingChanged,
    required this.whatsappPrice,
    required this.smsPricePerSegment,
    required this.smsSegments,
    required this.smsEncodingInfo,
    required this.onSmsPricingUpdate,
    required this.shopName,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _buildMessageAppEditor(context),
        SizedBox(height: SizeConfig.heightMultiplier * 1),
        Divider(
          color: Colors.grey,
          thickness: SizeConfig.heightMultiplier * 0,
        ),
        _buildPricingCard(),
      ],
    );
  }

  Widget _buildMessageAppEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hello [Customer Name],',
            style: TextStyle(fontStyle: FontStyle.italic)),
        SizedBox(height: SizeConfig.heightMultiplier * 1),
        TextFormField(
          controller: whatsappContentController,
          maxLines: 6,
          onChanged: (val) {
            onSmsPricingUpdate(val);
            if (includeSMS) {
              smsContentController.text = forceBoilerplate(val);
            }
          },
          decoration: const InputDecoration(
            labelText: 'Message',
            border: OutlineInputBorder(),
          ),
          validator: (val) => val == null || val.isEmpty || val.trim().isEmpty
              ? 'Message Body is required'
           : null,
        ),
        const SizedBox(height: 8),
        const Text('Kind regards,',
            style: TextStyle(fontStyle: FontStyle.italic)),
        Text('The $shopName team',
            style: const TextStyle(fontStyle: FontStyle.italic)),
        Divider(
          color: Colors.grey,
          thickness: SizeConfig.heightMultiplier * 0,
        ),
        if (includeWhatsApp) ...[
          _buildMediaSection(context),
        ],
      ],
    );
  }

  Widget _buildMediaSection(BuildContext context) {
    Future<void> _handleImageUpload() async {
      onImageUploadingChanged(true);
      await photoUtil.handleImagePick(context, (file) async {
        if (file != null) {
          final compressedFile = await photoUtil.compressImage(file);
          if (compressedFile != null) {
            final uploadPath =
                'whatsapp_media/${path.basename(compressedFile.path)}';
            final url = await photoUtil.uploadImage(compressedFile, uploadPath);
            if (url != null) {
              mediaUrlController.text = url;
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Failed to upload image. Try again.')),
              );
            }
          }
        }
        onImageUploadingChanged(false);
      });
    }

    Widget _mediaDisplay() {
      if (mediaUrlController.text.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            mediaUrlController.text,
            height: 100,
            width: 100,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, size: 80),
          ),
        );
      } else {
        return const SizedBox(
          height: 100,
          width: 100,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFE0E0E0),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            child: Center(child: Text('No image')),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('📷 Media (Whatsapp)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: uploadingImage ? null : _handleImageUpload,
              child: _mediaDisplay(),
            ),
            IconButton(
              icon: uploadingImage
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload),
              onPressed: uploadingImage ? null : _handleImageUpload,
            ),
          ],
        ),
        if (uploadingImage)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Uploading image...',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildPricingCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 4,
            vertical: SizeConfig.heightMultiplier * 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estimated Cost of Template',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            if (includeWhatsApp && whatsappPrice != null)
              Row(
                children: [
                  Icon(
                    FontAwesomeIcons.whatsapp,
                    color: Colors.green,
                    size: SizeConfig.textMultiplier * 2,
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  Text('WhatsApp: R${whatsappPrice!.toStringAsFixed(2)}'),
                ],
              ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            if (includeSMS && smsPricePerSegment != null)
              Row(
                children: [
                  Icon(
                    Icons.sms,
                    color: Colors.blue,
                    size: SizeConfig.textMultiplier * 2,
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  Expanded(
                    child: Text(
                      'SMS: $smsSegments segment(s) × R${smsPricePerSegment!.toStringAsFixed(2)} = R${(smsSegments * smsPricePerSegment!).toStringAsFixed(2)}',
                    ),
                  ),
                ],
              ),
            // QW-2: surface *why* a body is multipart so merchants can
            // self-rescue. UCS-2 flips are usually caused by characters
            // that look identical to GSM-7 equivalents on most handsets
            // (en-dash vs hyphen, curly vs straight quote) — without this
            // explanation the cost preview is a black box.
            if (includeSMS &&
                smsPricePerSegment != null &&
                smsEncodingInfo.offenderLabel != null)
              Padding(
                padding: EdgeInsets.only(
                  top: SizeConfig.heightMultiplier * 0.5,
                  left: SizeConfig.textMultiplier * 3.2,
                ),
                child: Text(
                  'This message contains ${smsEncodingInfo.offenderLabel}, '
                  'which forces a more expensive Unicode encoding. '
                  'Removing it can cut the cost in half.',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.4,
                    color: Colors.orange[800],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            Divider(
              color: Colors.grey,
              thickness: SizeConfig.heightMultiplier * 0,
            ),
            Text(
              'This is the cost per customer. Final cost will depend on how many customers you send to.',
              style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.5,
                  color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
