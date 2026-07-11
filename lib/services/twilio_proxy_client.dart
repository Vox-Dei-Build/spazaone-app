import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

typedef IdTokenProvider = Future<String?> Function();
typedef AppCheckTokenProvider = Future<String?> Function();

class TwilioProxyClient {
  static final Uri endpoint = Uri.parse(
    'https://us-central1-pasella-ledger.cloudfunctions.net/sendTwilioMessage',
  );

  final http.Client _httpClient;
  final IdTokenProvider _idTokenProvider;
  final AppCheckTokenProvider _appCheckTokenProvider;

  TwilioProxyClient({
    http.Client? httpClient,
    IdTokenProvider? idTokenProvider,
    AppCheckTokenProvider? appCheckTokenProvider,
  })  : _httpClient = httpClient ?? http.Client(),
        _idTokenProvider = idTokenProvider ??
            (() async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return null;
              return user.getIdToken();
            }),
        _appCheckTokenProvider = appCheckTokenProvider ??
            (() => FirebaseAppCheck.instance.getToken());

  Future<http.Response> post(Map<String, dynamic> payload) async {
    final idToken = await _idTokenProvider();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('A signed-in merchant is required to send messages.');
    }
    final appCheckToken = await _appCheckTokenProvider();
    if (appCheckToken == null || appCheckToken.isEmpty) {
      throw StateError('App verification is required to access messaging.');
    }

    return _httpClient.post(
      endpoint,
      headers: {
        'Authorization': 'Bearer $idToken',
        'X-Firebase-AppCheck': appCheckToken,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );
  }
}
