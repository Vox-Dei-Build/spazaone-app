import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pasella/config/remote_config.dart';

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

// Function to send a WhatsApp message using a template
  Future<String?> sendWhatsAppMessage(
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

    try {
      final response = await http.post(uri, headers: headers, body: body);

      if (response.statusCode == 201) {
        // HTTP 201 Created is expected
        final responseBody = json.decode(response.body);
        final String messageID = responseBody['sid'];
        // Return message ID for further processing (polling)
        return messageID;
      } else {
        print(
            'Failed to send WhatsApp message. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error sending WhatsApp message: $e');
      return null;
    }
  }

  Future<bool> pollMessageStatus(String messageSid) async {
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
            status == 'canceled') {
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
}
