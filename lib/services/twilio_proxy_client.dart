import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

typedef IdTokenProvider = Future<String?> Function();

class TwilioProxyClient {
  static final Uri endpoint = Uri.parse(
    'https://us-central1-pasella-ledger.cloudfunctions.net/sendTwilioMessage',
  );

  final http.Client _httpClient;
  final IdTokenProvider _idTokenProvider;

  TwilioProxyClient({
    http.Client? httpClient,
    IdTokenProvider? idTokenProvider,
  })  : _httpClient = httpClient ?? http.Client(),
        _idTokenProvider = idTokenProvider ??
            (() async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return null;
              return user.getIdToken();
            });

  Future<http.Response> post(Map<String, dynamic> payload) async {
    final idToken = await _idTokenProvider();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('A signed-in merchant is required to send messages.');
    }

    return _httpClient.post(
      endpoint,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );
  }
}
