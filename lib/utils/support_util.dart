import 'package:flutter/material.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:url_launcher/url_launcher.dart';

enum WhatsAppMessageType {
  support,
  feedback,
  sales,
  bug,
  other,
}

class SupportUtil {
  static Future<void> sendWhatsAppMessage(
      BuildContext context, WhatsAppMessageType type) async {
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
      final String message = Uri.encodeComponent(_getMessageTemplate(type));

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
      print('WhatsApp Error: $e');
    }
  }

  static String _getMessageTemplate(WhatsAppMessageType type) {
    switch (type) {
      case WhatsAppMessageType.feedback:
        return "Hi Spaza One Support 👋,\n\nI’d like to leave feedback about the app experience. 📝\nHere’s what I think:";
      case WhatsAppMessageType.sales:
        return "Hi Spaza One Team 👋,\n\nI'm interested in increasing my sales. Can you share some tips or features I can use? 💰";
      case WhatsAppMessageType.bug:
        return "Hi Spaza One Support 👋,\n\nI found a bug 🐛 in the app. Here's what happened:";
      case WhatsAppMessageType.other:
        return "Hi Spaza One 👋,\n\nI have a general question or request.";
      case WhatsAppMessageType.support:
        return "Hi Spaza One Support 👋,\n\nI need assistance with something on the app. Could you please help me out?\n\nThanks! 😊";
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
