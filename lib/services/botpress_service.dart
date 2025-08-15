import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/utils/phone_util.dart';

class BotpressService {
  BotpressService._(this._apiToken) : _http = http.Client();

  final String _apiToken;
  final http.Client _http;

  static Future<BotpressService> create() async {
    final remoteConfigService = await RemoteConfigService.getInstance();
    final token = remoteConfigService.getString('Botpress_Keys');
    return BotpressService._(token);
  }

  Future<List<Map<String, dynamic>>> fetchBotpressMessages({
    required String customerNumber,
  }) async {
    final whatsappNumber = formatForTwilio(customerNumber, true);
    final uri = Uri.parse(
        'https://api.botpress.cloud/v1/users/$whatsappNumber/messages');

    try {
      final response = await _http.get(uri, headers: {
        'Authorization': 'Bearer $_apiToken',
      });

      if (response.statusCode != 200) {
        print('❌ Botpress API Error: ${response.statusCode} - ${response.body}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> rawMessages =
          (data['messages'] ?? data['items'] ?? []) as List<dynamic>;

      return rawMessages.map<Map<String, dynamic>>((msg) {
        final createdAt = msg['createdAt'] ?? msg['created_at'];
        final direction = msg['direction'] ?? '';
        final payload = msg['payload'] ?? {};
        final text = payload['text'] ?? '';
        String? mediaUrl;
        final media = msg['media'];
        if (media is List && media.isNotEmpty) {
          final first = media.first;
          if (first is Map<String, dynamic>) {
            mediaUrl = first['url'] ?? first['src'];
          }
        }
        return {
          'id': msg['id'],
          'message': text,
          'dateSent': createdAt != null
              ? DateTime.parse(createdAt.toString())
              : DateTime.now(),
          'direction': direction,
          'isWhatsApp': true,
          'isSMS': false,
          'isAI': direction == 'outbound',
          'mediaUrl': mediaUrl,
        };
      }).toList();
    } catch (e, stack) {
      print('🔥 Error fetching Botpress messages: $e');
      print('📜 StackTrace: $stack');
      return [];
    }
  }
}

