import 'package:flutter/material.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/force_boilerplate.dart';
import 'package:pasella/utils/photo_upload_util.dart';
import 'package:pasella/utils/sms_pricing_util.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/utils/currency_util.dart';

class ContentStep extends StatelessWidget {
  final bool includeWhatsApp;
  final bool includeSMS;
  final TextEditingController whatsappContentController;
  final TextEditingController smsContentController;
  final TextEditingController mediaUrlController;

  /// Nullable so the message editor can be rendered in isolation (for
  /// previews/tests). The production template flow always supplies it.
  final PhotoUploadUtil? photoUtil;
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
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      children: [
        const _TemplatePurposeNotice(),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        _buildMessageAppEditor(context),
        SizedBox(height: SizeConfig.heightMultiplier * 1),
        Divider(color: Colors.grey, thickness: SizeConfig.heightMultiplier * 0),
        _buildPricingCard(),
      ],
    );
  }

  Widget _buildMessageAppEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Write the message customers will receive',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Keep it reusable. You will choose the customers and attach a '
          'product after WhatsApp approves this template.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 1.5),
        const Text(
          'Hello [Customer Name],',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 1),
        TextFormField(
          controller: whatsappContentController,
          minLines: 4,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (val) {
            onSmsPricingUpdate(val);
            if (includeSMS) {
              smsContentController.text = forceBoilerplate(val);
            }
          },
          decoration: const InputDecoration(
            labelText: 'Promotion message *',
            hintText: 'Example: Fresh bread is available today. Reply '
                'CATALOG to view our products and place an order.',
            helperText: 'Type your offer here to unlock the next step.',
            helperMaxLines: 2,
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          validator: (val) => val == null || val.isEmpty || val.trim().isEmpty
              ? 'Message Body is required'
              : null,
        ),
        const SizedBox(height: 8),
        const Text(
          'Kind regards,',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
        // PAS-UX-09 follow-up: shopName may be blank for legacy merchants;
        // avoid rendering "The  team" in the preview.
        Text(
          shopName.trim().isEmpty
              ? 'The SpazaOne team'
              : 'The ${shopName.trim()} team',
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
        Divider(color: Colors.grey, thickness: SizeConfig.heightMultiplier * 0),
        if (includeWhatsApp) ...[_buildMediaSection(context)],
      ],
    );
  }

  Widget _buildMediaSection(BuildContext context) {
    Future<void> handleImageUpload() async {
      final uploader = photoUtil;
      if (uploader == null) return;
      onImageUploadingChanged(true);
      await uploader.handleImagePick(context, (file) async {
        if (file != null) {
          final compressedFile = await uploader.compressImage(file);
          if (compressedFile != null) {
            final uploadPath =
                'whatsapp_media/${StoreSession.instance.storeId}/'
                '${compressedFile.uri.pathSegments.last}';
            final url = await uploader.uploadImage(compressedFile, uploadPath);
            if (url != null) {
              mediaUrlController.text = url;
            } else {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to upload image. Try again.'),
                ),
              );
            }
          }
        }
        onImageUploadingChanged(false);
      });
    }

    Widget mediaDisplay() {
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
        const Text(
          'Optional WhatsApp image',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'This image becomes part of the approved template. A product can '
          'still be attached later when you run the promotion.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: uploadingImage ? null : handleImageUpload,
              child: mediaDisplay(),
            ),
            IconButton(
              icon: uploadingImage
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload),
              onPressed: uploadingImage ? null : handleImageUpload,
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
          vertical: SizeConfig.heightMultiplier * 1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estimated delivery cost per customer',
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
                  Text('WhatsApp: ${CurrencyUtil.format(whatsappPrice!)}'),
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
                      'SMS: $smsSegments segment(s) × ${CurrencyUtil.format(smsPricePerSegment!)} = ${CurrencyUtil.format(smsSegments * smsPricePerSegment!)}',
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
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains the boundary that confused the release customer: this step creates
/// an approved reusable message; recipients and products belong to the later
/// Run Promotion flow.
class _TemplatePurposeNotice extends StatelessWidget {
  const _TemplatePurposeNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Step 1 of 2: create a reusable message for WhatsApp approval. '
              'After approval, run a promotion to attach a stock product and '
              'choose who receives it.',
            ),
          ),
        ],
      ),
    );
  }
}
