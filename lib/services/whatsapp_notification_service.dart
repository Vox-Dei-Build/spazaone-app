import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/templates/whatsapp_message.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:url_launcher/url_launcher.dart';

class WhatsAppNotificationService {
  Future<void> sendFormattedWhatsapp(
    String currentUserId,
    String customerId,
    String customerName,
    String message,
  ) async {
    try {
      String? phoneNumber =
          await fetchAndFormatPhoneNumberForWhatsApp(currentUserId, customerId);

      if (isValidSAPhoneNumber(phoneNumber) && phoneNumber != null) {
        String shopName =
            await fetchShopNameForUser(currentUserId) ?? 'The Corner Shop';

        double balance = await CurrencyUtil.fetchCurrentBalanceForCustomer(
            currentUserId, customerId);

        message = message.replaceAll('{balance}', CurrencyUtil.format(balance));
        message = message.replaceAll('{shopName}', shopName);
        message = message.replaceAll('{customerName}', customerName);

        final encodedMessage = Uri.encodeComponent(message);
        final url =
            Uri.parse('https://wa.me/$phoneNumber?text=$encodedMessage');

        if (await canLaunchUrl(url)) {
          await launchUrl(url);

          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUserId)
              .collection('customers')
              .doc(customerId)
              .collection('reminders')
              .add({
            'message': message,
            'dateSent': Timestamp.now(),
          });
        }
      }
    } catch (e) {
      print("Could not launch Whatsapp or send a message : $e");
    }
  }

  Future<void> sendReminderWhatsapp(
      String currentUserId, String customerId, String customerName) async {
    try {
      await sendFormattedWhatsapp(currentUserId, customerId, customerName,
          WhatsAppMessages.reminderMessage);
    } catch (e) {
      print('Error occurred while sending confirmation SMS: $e');
    }
  }
}
