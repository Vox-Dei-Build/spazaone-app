import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/templates/whatsapp_message.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:url_launcher/url_launcher.dart';

class WhatsAppMessagingService {
  late final String accountSid;
  late final String authToken;
  late final String fromNumber;
  late final String messagingServiceSid;

  WhatsAppMessagingService() {
    final remoteConfigService = RemoteConfigService.createInstance();
    accountSid = remoteConfigService.getString('TWILIO_ACCOUNT_SID')!;
    authToken = remoteConfigService.getString('TWILIO_AUTH_TOKEN')!;
    fromNumber = remoteConfigService.getString('TWILIO_NUMBER')!;
    messagingServiceSid =
        remoteConfigService.getString('TWILIO_MESSAGING_SERVICE_ID')!;
  }

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

  // Function to send a WhatsApp message using a template
  Future<bool> sendWhatsAppMessage(
      String to, String templateSid, Map<String, dynamic> variables) async {
    final uri = Uri.parse(
        'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json');
    final headers = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Authorization':
          'Basic ' + base64Encode(utf8.encode('$accountSid:$authToken'))
    };

    String encodedVariables = json.encode(variables);

    final body = {
      'To': 'whatsapp:$to',
      'From': messagingServiceSid,
      'ContentSid': templateSid,
      'ContentVariables': encodedVariables,
    };

    final response = await http.post(
      uri,
      headers: headers,
      body: body,
    );

    final responseBody = json.decode(response.body);
    final String messageID = responseBody['sid'];

    return pollMessageStatus(messageID, accountSid, authToken);
  }

  Future<bool> pollMessageStatus(
      String messageSid, String accountSid, String authToken) async {
    final statusUri = Uri.parse(
        'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages/$messageSid.json');
    final headers = {
      'Authorization':
          'Basic ' + base64Encode(utf8.encode('$accountSid:$authToken'))
    };

    int delaySeconds = 1; // Start with 1 seconds
    bool isFinalStatus = false;

    while (!isFinalStatus) {
      await Future.delayed(Duration(seconds: delaySeconds));
      final response = await http.get(statusUri, headers: headers);

      if (response.statusCode == 200) {
        final status = json.decode(response.body)['status'];

        if (status == 'delivered' ||
            status == 'failed' ||
            status == 'undelivered' ||
            status == 'canceled' ||
            status == 'sent' ||
            status == 'accepted' ||
            status == 'read' ||
            status == 'received') {
          isFinalStatus = true;
          return status == 'delivered';
        } else {
          delaySeconds = (delaySeconds < 60)
              ? delaySeconds * 2
              : 60; // Exponential backoff, cap at 60 seconds
        }
      } else {
        return false;
      }
    }

    return false;
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
