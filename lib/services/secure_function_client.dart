import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class SecureFunctionClient {
  SecureFunctionClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<http.Response> post(
    Uri endpoint,
    Map<String, dynamic> payload,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    final appCheckToken = await FirebaseAppCheck.instance.getToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('A signed-in merchant is required.');
    }
    if (appCheckToken == null || appCheckToken.isEmpty) {
      throw StateError('App verification is required.');
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
