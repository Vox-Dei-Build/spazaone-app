import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/templates/sms_message.dart';
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

  /// ✅ Helper: Fetch customer details from Firestore
  Future<Map<String, dynamic>?> _fetchCustomerDetails(
      String userId, String customerId) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('customers')
        .doc(customerId)
        .get();
    return doc.exists ? doc.data() : null;
  }

  /// ✅ Helper: Fetch merchant details from Firestore
  Future<Map<String, dynamic>?> _fetchMerchantDetails(String userId) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return doc.exists ? doc.data() : null;
  }

  /// ✅ Helper: Fetch messages from Twilio API
  Future<List<Map<String, dynamic>>> _fetchTwilioMessages(
      String toQuery) async {
    final url = Uri.parse(
        'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json?To=${Uri.encodeComponent(toQuery)}');

    final response = await http.get(url, headers: {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      return List<Map<String, dynamic>>.from(data['messages'].map((msg) => {
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
            'isWhatsApp': msg['from'].contains('whatsapp') ||
                msg['to'].contains('whatsapp'),
          }));
    } else {
      print("❌ Twilio API Error: ${response.statusCode} - ${response.body}");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchMessagesToCustomer({
    required String customerNumber,
    required String currentUserId,
    required String customerId,
  }) async {
    final smsToQuery = formatForTwilio(customerNumber, false); // "+27..."
    final whatsappToQuery =
        formatForTwilio(customerNumber, true); // "whatsapp:+27..."

    try {
      // ✅ Fetch SMS & WhatsApp Messages in parallel
      final messagesFuture = Future.wait([
        _fetchTwilioMessages(smsToQuery),
        _fetchTwilioMessages(whatsappToQuery),
        _fetchCustomerDetails(currentUserId, customerId),
        _fetchMerchantDetails(currentUserId),
      ]);

      // ✅ Wait for all tasks to complete
      final results = await messagesFuture;

      // Ensure the results are cast to List<Map<String, dynamic>>? before spreading
      final List<Map<String, dynamic>> allMessages = [
        ...?results[0] as List<
            Map<String, dynamic>>?, // ✅ Ensures it's a list before spreading
        ...?results[1] as List<
            Map<String, dynamic>>?, // ✅ Ensures it's a list before spreading
      ];

      final Map<String, dynamic>? customerData =
          results[2] as Map<String, dynamic>?;
      final Map<String, dynamic>? merchantData =
          results[3] as Map<String, dynamic>?;

      // 🔥 Extract customer & merchant details
      final customerName = customerData?['name'] ?? "";
      final shopName = merchantData?['shopName'] ?? "";

      // 🔥 Step 2: Identify & Verify Template Messages
      List<Map<String, dynamic>> filteredMessages =
          allMessages.where((message) {
        final messageText = message['message'];
        final isWhatsApp = message['isWhatsApp'] ?? false;

        bool isTemplateMessage = isWhatsApp
            ? SMSMessages.isTemplateMessage(
                messageText) // WhatsApp template detection
            : true; // All SMS messages are templates

        if (isTemplateMessage) {
          // ✅ Verified Template Message from the correct merchant. Keeping it.
          if (messageText.contains(customerName) ||
              messageText.contains(shopName)) {
            return true;
          } else {
            // 🚨 Template Message Mismatch! Likely from another merchant. Discarding."
            return false;
          }
        } else {
          // "🛠 AI Bot or General Message Detected. Keeping it.
          message['isAI'] = true;
          return true;
        }
      }).toList();

      // ✅ Sort by date (latest at the bottom)
      filteredMessages.sort((a, b) => a['dateSent'].compareTo(b['dateSent']));
      return filteredMessages;
    } catch (e, stackTrace) {
      print("🔥 Error processing messages: $e");
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
    List<Map<String, dynamic>> allMessages = [];

    try {
      // ✅ Fetch SMS messages
      final smsUrl = Uri.parse(
          'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json?From=${Uri.encodeComponent(smsFromQuery)}');

      final smsResponse = await http.get(smsUrl, headers: {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}',
      });

      if (smsResponse.statusCode == 200) {
        final smsData = jsonDecode(smsResponse.body);

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

      final whatsappResponse = await http.get(whatsappUrl, headers: {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}',
      });

      if (whatsappResponse.statusCode == 200) {
        final whatsappData = jsonDecode(whatsappResponse.body);

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

      return allMessages;
    } catch (e, stackTrace) {
      print("🔥 Error fetching messages: $e");
      print("📜 StackTrace: $stackTrace");
      return [];
    }
  }
}
