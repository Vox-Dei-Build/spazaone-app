import 'package:flutter/material.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportUtil {
  static Future<void> sendSupportWhatsAppMessage(BuildContext context) async {
    try {
      final remoteConfigService = await RemoteConfigService.getInstance();
      final String supportNumber =
          remoteConfigService.getString('WA_SUPPORT_NUMBER');

      if (supportNumber.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Support number is unavailable')),
        );
        return;
      }

      final String formattedNumber =
          formatPhoneNumberForWhatsapp(supportNumber);
      final String message = Uri.encodeComponent(
        "Hi Pasella Support 👋,\n\nI need assistance with something on the app. Could you please help me out?\n\nThanks! 😊",
      );

      final Uri whatsappUri =
          Uri.parse('https://wa.me/$formattedNumber?text=$message');

      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else {
        _showCallSnackbar(context, supportNumber);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not open WhatsApp support message.')),
      );
      print('Support WhatsApp Error: $e');
    }
  }

  static void _showCallSnackbar(BuildContext context, String phone) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open WhatsApp. Try calling $phone instead.'),
        action: SnackBarAction(
          label: 'Call',
          onPressed: () {
            launchUrl(Uri.parse('tel:$phone'),
                mode: LaunchMode.externalApplication);
          },
        ),
      ),
    );
  }
}
