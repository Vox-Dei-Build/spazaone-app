import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/templates/sms_message.dart';
import 'package:pasella/utils/phone_util.dart';

class TwilioService {
  TwilioService._(this.accountSid, this.authToken) : _http = http.Client();

  late String accountSid;
  late String authToken;
  final http.Client _http;

  static Future<TwilioService> create() async {
    final remoteConfigService = await RemoteConfigService.getInstance();
    return TwilioService._(
      remoteConfigService.getString('TWILIO_ACCOUNT_SID'),
      remoteConfigService.getString('TWILIO_AUTH_TOKEN'),
    );
  }

  String buildMediaJsonPath(String messagePath) {
    // 1) Strip any existing query params
    final raw = messagePath.split('.json').first;
    // 2) Ensure it doesn't already end in “Media.json”
    if (raw.endsWith('/Media.json')) return raw;
    // 3) Append “/Media.json”
    return raw.endsWith('/') ? '${raw}Media.json' : '$raw/Media.json';
  }

  Future<List<String>> fetchMediaUrls(String mediaResourceUri) async {
    final creds = base64Encode(utf8.encode('$accountSid:$authToken'));

    // Strip off any query string and ensure leading slash
    final rawPath = mediaResourceUri.split('?').first;
    final path = rawPath.startsWith('/') ? rawPath : '/$rawPath';

    final uri = Uri.https('api.twilio.com', path);
    final resp = await _http.get(uri, headers: {
      'Authorization': 'Basic $creds',
    });
    if (resp.statusCode != 200) {
      throw Exception('Failed to load media JSON: ${resp.statusCode}');
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final mediaList = (body['media_list'] as List).cast<Map<String, dynamic>>();

    // Map each metadata item to its raw URL
    return mediaList.map((item) {
      final itemUri = (item['uri'] as String).replaceFirst('.json', '');
      return 'https://api.twilio.com$itemUri';
    }).toList();
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
      // Fetch outbound SMS & WhatsApp in parallel. Both Twilio queries are
      // recipient-scoped (`To=<customerNumber>` / `To=whatsapp:<customerNumber>`),
      // which Twilio enforces server-side, so every row returned is already
      // for THIS customer's thread. We must not further filter by message
      // body: doing so previously hid legitimate Botpress / WhatsApp replies
      // whose payloads (balance, statement, card menus, media-only, etc.)
      // do not contain the customer name or shop name.
      final results = await Future.wait([
        _fetchTwilioMessages(smsToQuery),
        _fetchTwilioMessages(whatsappToQuery),
      ]);

      final List<Map<String, dynamic>> allMessages = [
        ...?results[0] as List<Map<String, dynamic>>?,
        ...?results[1] as List<Map<String, dynamic>>?,
      ];

      // Classify non-template outbound WhatsApp as AI (badge only — does not
      // affect visibility). SMS-channel Botpress replies are not produced by
      // the bot, so SMS is treated as template by default.
      for (final message in allMessages) {
        final messageText = (message['message'] ?? '').toString();
        final isWhatsApp = message['isWhatsApp'] == true;
        final bool isTemplateMessage = isWhatsApp
            ? await SMSMessages.isTemplateMessage(messageText)
            : true;
        if (!isTemplateMessage) {
          message['isAI'] = true;
        }
      }

      // 1️⃣ First, convert the string "num_media" into an integer field
      for (var msg in allMessages) {
        // Twilio returns it as a string, e.g. "3"
        final raw = msg['num_media'] ?? msg['num_media'] ?? '0';
        // parse safely
        msg['num_media'] = int.tryParse(raw.toString()) ?? 0;
      }

      // 2️⃣ Now pick only those with attachments
      final withMedia =
          allMessages.where((m) => (m['num_media'] as int) > 0).toList();

      // 3️⃣ Fire off all fetchMediaUrls in parallel
      await Future.wait(withMedia.map((msg) async {
        final String? mediaUri = (msg['uri']) as String?;
        if (mediaUri != null && mediaUri.isNotEmpty) {
          final mediaJsonPath = buildMediaJsonPath(mediaUri);
          try {
            // fetchMediaUrls handles both full & relative URIs
            final urls = await fetchMediaUrls(mediaJsonPath);
            msg['mediaUrl'] = urls.isNotEmpty ? urls.first : null;
          } catch (_) {
            msg['mediaUrl'] = null;
          }
        } else {
          msg['mediaUrl'] = null;
        }
      }));

      // ✅ Sort by date (latest at the bottom). Return every recipient-scoped
      // outbound message — visibility is gated solely by Twilio's `To=` query.
      allMessages.sort((a, b) => a['dateSent'].compareTo(b['dateSent']));
      return allMessages;
    } catch (e, stackTrace) {
      await CrashService.instance.recordNonFatal(
        e,
        stackTrace,
        reason: 'twilio fetchMessagesToCustomer failed',
      );
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
                        .parseUtc(msg['date_sent'])
                    : DateTime.now(),
                'status': msg['status'],
                'direction': "inbound",
                'num_media': msg['num_media'] ?? 0,
                'from': msg['from'],
                'to': msg['to'],
                'mediaUrl': msg['uri'] ?? '',
                'isWhatsApp': false, // ✅ Mark as SMS
              })),
        );
      } else {
        await CrashService.instance.recordNonFatal(
          'Twilio SMS API non-200',
          StackTrace.current,
          reason: 'twilio fetchMessagesFromCustomer SMS API error',
          context: {'status_code': smsResponse.statusCode},
        );
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
                            .parseUtc(msg['date_sent'])
                        : DateTime.now(),
                    'status': msg['status'],
                    'direction': "inbound",
                    'from': msg['from'],
                    'to': msg['to'],
                    'num_media': msg['num_media'] ?? 0,
                    'isWhatsApp': true, // ✅ Mark as WhatsApp
                  })),
        );
      } else {
        await CrashService.instance.recordNonFatal(
          'Twilio WhatsApp API non-200',
          StackTrace.current,
          reason: 'twilio fetchMessagesFromCustomer WhatsApp API error',
          context: {'status_code': whatsappResponse.statusCode},
        );
      }

      // 1️⃣ First, convert the string "num_media" into an integer field
      for (var msg in allMessages) {
        // Twilio returns it as a string, e.g. "3"
        final raw = msg['num_media'] ?? msg['num_media'] ?? '0';
        // parse safely
        msg['num_media'] = int.tryParse(raw.toString()) ?? 0;
      }

      // 2️⃣ Now pick only those with attachments
      final withMedia =
          allMessages.where((m) => (m['num_media'] as int) > 0).toList();

      // 3️⃣ Fire off all fetchMediaUrls in parallel
      await Future.wait(withMedia.map((msg) async {
        final String? mediaUri = (msg['uri']) as String?;
        if (mediaUri != null && mediaUri.isNotEmpty) {
          final mediaJsonPath = buildMediaJsonPath(mediaUri);
          try {
            // fetchMediaUrls handles both full & relative URIs
            final urls = await fetchMediaUrls(mediaJsonPath);
            msg['mediaUrl'] = urls.isNotEmpty ? urls.first : null;
          } catch (_) {
            msg['mediaUrl'] = null;
          }
        } else {
          msg['mediaUrl'] = null;
        }
      }));
      allMessages.sort((a, b) => b['dateSent'].compareTo(a['dateSent']));

      return allMessages;
    } catch (e, stackTrace) {
      await CrashService.instance.recordNonFatal(
        e,
        stackTrace,
        reason: 'twilio fetchMessagesFromCustomer failed',
      );
      return [];
    }
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
                    .parseUtc(msg['date_sent'])
                : DateTime.now(),
            'status': msg['status'],
            'direction': "outbound",
            'from': msg['from'],
            'to': msg['to'],
            'uri': msg['uri'],
            'num_media': msg['num_media'] ?? 0,
            'isWhatsApp': msg['from'].contains('whatsapp') ||
                msg['to'].contains('whatsapp'),
          }));
    } else {
      await CrashService.instance.recordNonFatal(
        'Twilio API non-200',
        StackTrace.current,
        reason: 'twilio _fetchTwilioMessages API error',
        context: {'status_code': response.statusCode},
      );
      return [];
    }
  }
}
