import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/utils/phone_util.dart';

class TwilioService {
  late String accountSid;
  late String authToken;

  TwilioService._(this.accountSid, this.authToken);

  static Future<TwilioService> create() async {
    final remoteConfigService = await RemoteConfigService.getInstance();

    return TwilioService._(
      remoteConfigService.getString('TWILIO_ACCOUNT_SID'),
      remoteConfigService.getString('TWILIO_AUTH_TOKEN'),
    );
  }

  Future<List<Map<String, dynamic>>> fetchMessagesToCustomer({
    required String customerNumber,
    required String twilioSmsNumber,
    required String twilioMessagingServiceId,
  }) async {
    // ✅ Format numbers correctly
    final smsToQuery = formatForTwilio(customerNumber, false); // "+27..."
    final whatsappToQuery =
        formatForTwilio(customerNumber, true); // "whatsapp:+27..."

    print("📡 Fetching messages sent TO Customer: $customerNumber...");
    print("📩 SMS Query: $smsToQuery");
    print("📩 WhatsApp Query: $whatsappToQuery");

    List<Map<String, dynamic>> allMessages = [];

    try {
      // ✅ First API call: Fetch SMS messages
      final smsUrl = Uri.parse(
          'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json?To=${Uri.encodeComponent(smsToQuery)}');

      print("🔗 Fetching SMS messages from: $smsUrl");
      final smsResponse = await http.get(smsUrl, headers: {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}',
      });

      if (smsResponse.statusCode == 200) {
        final smsData = jsonDecode(smsResponse.body);
        print("✅ Fetched ${smsData['messages'].length} SMS messages.");

        allMessages.addAll(
          List<Map<String, dynamic>>.from(smsData['messages'].map((msg) => {
                'sid': msg['sid'],
                'message': msg['body'],
                'dateSent': msg['date_sent'] != null
                    ? DateFormat("EEE, dd MMM yyyy HH:mm:ss Z")
                        .parse(msg['date_sent'])
                    : DateTime.now(),
                'status': msg['status'],
                'direction': "outbound",
                'from': msg['from'],
                'to': msg['to'],
                'isWhatsApp': false, // ✅ Mark as SMS
              })),
        );
      } else {
        print(
            "❌ Twilio SMS API Error: ${smsResponse.statusCode} - ${smsResponse.body}");
      }

      // ✅ Second API call: Fetch WhatsApp messages
      final whatsappUrl = Uri.parse(
          'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json?To=${Uri.encodeComponent(whatsappToQuery)}');

      print("🔗 Fetching WhatsApp messages from: $whatsappUrl");
      final whatsappResponse = await http.get(whatsappUrl, headers: {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}',
      });

      if (whatsappResponse.statusCode == 200) {
        final whatsappData = jsonDecode(whatsappResponse.body);
        print(
            "✅ Fetched ${whatsappData['messages'].length} WhatsApp messages.");

        allMessages.addAll(
          List<Map<String, dynamic>>.from(
              whatsappData['messages'].map((msg) => {
                    'sid': msg['sid'],
                    'message': msg['body'],
                    'dateSent': msg['date_sent'] != null
                        ? DateFormat("EEE, dd MMM yyyy HH:mm:ss Z")
                            .parse(msg['date_sent'])
                        : DateTime.now(),
                    'status': msg['status'],
                    'direction': "outbound",
                    'from': msg['from'],
                    'to': msg['to'],
                    'isWhatsApp': true, // ✅ Mark as WhatsApp
                  })),
        );
      } else {
        print(
            "❌ Twilio WhatsApp API Error: ${whatsappResponse.statusCode} - ${whatsappResponse.body}");
      }

      // ✅ Sort messages by date (latest first)
      allMessages.sort((a, b) => b['dateSent'].compareTo(a['dateSent']));
      print("✅ Merged ${allMessages.length} total messages.");

      return allMessages;
    } catch (e, stackTrace) {
      print("🔥 Error fetching messages: $e");
      print("📜 StackTrace: $stackTrace");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchMessagesFromCustomer({
    required String customerNumber,
    required String twilioSmsNumber,
    required String twilioMessagingServiceId,
  }) async {
    final smsFromQuery = formatForTwilio(customerNumber, false); // "+27..."
    final whatsappFromQuery =
        formatForTwilio(customerNumber, true); // "whatsapp:+27..."

    print("📡 Fetching messages FROM Customer: $customerNumber...");
    print("📩 SMS Query: $smsFromQuery");
    print("📩 WhatsApp Query: $whatsappFromQuery");

    List<Map<String, dynamic>> allMessages = [];

    try {
      // ✅ Fetch SMS messages
      final smsUrl = Uri.parse(
          'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json?From=${Uri.encodeComponent(smsFromQuery)}');

      print("🔗 Fetching SMS messages from: $smsUrl");
      final smsResponse = await http.get(smsUrl, headers: {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}',
      });

      if (smsResponse.statusCode == 200) {
        final smsData = jsonDecode(smsResponse.body);
        print("✅ Fetched ${smsData['messages'].length} SMS messages.");

        allMessages.addAll(
          List<Map<String, dynamic>>.from(smsData['messages'].map((msg) => {
                'sid': msg['sid'],
                'message': msg['body'],
                'dateSent': msg['date_sent'] != null
                    ? DateFormat("EEE, dd MMM yyyy HH:mm:ss Z")
                        .parse(msg['date_sent'])
                    : DateTime.now(),
                'status': msg['status'],
                'direction': "inbound",
                'from': msg['from'],
                'to': msg['to'],
                'isWhatsApp': false, // ✅ Mark as SMS
              })),
        );
      } else {
        print(
            "❌ Twilio SMS API Error: ${smsResponse.statusCode} - ${smsResponse.body}");
      }

      // ✅ Fetch WhatsApp messages
      final whatsappUrl = Uri.parse(
          'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json?From=${Uri.encodeComponent(whatsappFromQuery)}');

      print("🔗 Fetching WhatsApp messages from: $whatsappUrl");
      final whatsappResponse = await http.get(whatsappUrl, headers: {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}',
      });

      if (whatsappResponse.statusCode == 200) {
        final whatsappData = jsonDecode(whatsappResponse.body);
        print(
            "✅ Fetched ${whatsappData['messages'].length} WhatsApp messages.");

        allMessages.addAll(
          List<Map<String, dynamic>>.from(
              whatsappData['messages'].map((msg) => {
                    'sid': msg['sid'],
                    'message': msg['body'],
                    'dateSent': msg['date_sent'] != null
                        ? DateFormat("EEE, dd MMM yyyy HH:mm:ss Z")
                            .parse(msg['date_sent'])
                        : DateTime.now(),
                    'status': msg['status'],
                    'direction': "inbound",
                    'from': msg['from'],
                    'to': msg['to'],
                    'isWhatsApp': true, // ✅ Mark as WhatsApp
                  })),
        );
      } else {
        print(
            "❌ Twilio WhatsApp API Error: ${whatsappResponse.statusCode} - ${whatsappResponse.body}");
      }

      allMessages.sort((a, b) => b['dateSent'].compareTo(a['dateSent']));
      print("✅ Merged ${allMessages.length} total messages.");

      return allMessages;
    } catch (e, stackTrace) {
      print("🔥 Error fetching messages: $e");
      print("📜 StackTrace: $stackTrace");
      return [];
    }
  }
}
