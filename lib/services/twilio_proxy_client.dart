import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:pasella/services/store_session.dart';
import 'package:pasella/config/function_endpoints.dart';

typedef IdTokenProvider = Future<String?> Function();
typedef AppCheckTokenProvider = Future<String?> Function();
typedef RetryDelay = Future<void> Function(Duration duration);
typedef StoreIdProvider = String Function();

class TwilioProxyClient {
  static Uri get endpoint => FunctionEndpoints.https('sendTwilioMessage');

  final Uri _endpoint;
  final http.Client _httpClient;
  final IdTokenProvider _idTokenProvider;
  final AppCheckTokenProvider _appCheckTokenProvider;
  final IdTokenProvider _refreshedIdTokenProvider;
  final AppCheckTokenProvider _refreshedAppCheckTokenProvider;
  final RetryDelay _retryDelay;
  final StoreIdProvider _storeIdProvider;

  TwilioProxyClient({
    http.Client? httpClient,
    IdTokenProvider? idTokenProvider,
    AppCheckTokenProvider? appCheckTokenProvider,
    IdTokenProvider? refreshedIdTokenProvider,
    AppCheckTokenProvider? refreshedAppCheckTokenProvider,
    RetryDelay? retryDelay,
    Uri? endpoint,
    StoreIdProvider? storeIdProvider,
  })  : _httpClient = httpClient ?? http.Client(),
        _endpoint = endpoint ?? TwilioProxyClient.endpoint,
        _storeIdProvider =
            storeIdProvider ?? (() => StoreSession.instance.storeId),
        _idTokenProvider = idTokenProvider ??
            (() async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return null;
              return user.getIdToken();
            }),
        _appCheckTokenProvider = appCheckTokenProvider ??
            (() => FirebaseAppCheck.instance.getToken()),
        _refreshedIdTokenProvider = refreshedIdTokenProvider ??
            idTokenProvider ??
            (() async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return null;
              return user.getIdToken(true);
            }),
        _refreshedAppCheckTokenProvider = refreshedAppCheckTokenProvider ??
            appCheckTokenProvider ??
            (() => FirebaseAppCheck.instance.getToken(true)),
        _retryDelay =
            retryDelay ?? ((duration) => Future<void>.delayed(duration));

  Future<http.Response> post(Map<String, dynamic> payload) async {
    _ProxyTokens tokens;
    try {
      tokens = await _loadTokens(forceRefresh: false);
    } catch (_) {
      // Play Integrity/App Check can still be warming up immediately after a
      // cold app start. Retry once with forced token refresh instead of
      // silently dropping the merchant's first message attempt.
      await _retryDelay(const Duration(milliseconds: 300));
      tokens = await _loadTokens(forceRefresh: true);
    }

    var response = await _send(payload, tokens);
    if (response.statusCode == 401 || response.statusCode == 403) {
      // A cached Firebase Auth or App Check token may have expired between
      // acquisition and validation. Refresh both credentials and retry the
      // exact request once; never send without either security token.
      tokens = await _loadTokens(forceRefresh: true);
      response = await _send(payload, tokens);
    }

    return response;
  }

  Future<_ProxyTokens> _loadTokens({required bool forceRefresh}) async {
    final idToken =
        await (forceRefresh ? _refreshedIdTokenProvider() : _idTokenProvider());
    if (idToken == null || idToken.isEmpty) {
      throw StateError('A signed-in merchant is required to send messages.');
    }
    final appCheckToken = await (forceRefresh
        ? _refreshedAppCheckTokenProvider()
        : _appCheckTokenProvider());
    if (appCheckToken == null || appCheckToken.isEmpty) {
      throw StateError('App verification is required to access messaging.');
    }

    return _ProxyTokens(idToken, appCheckToken);
  }

  Future<http.Response> _send(
    Map<String, dynamic> payload,
    _ProxyTokens tokens,
  ) {
    return _httpClient.post(
      _endpoint,
      headers: {
        'Authorization': 'Bearer ${tokens.idToken}',
        'X-Firebase-AppCheck': tokens.appCheckToken,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        ...payload,
        if (!payload.containsKey('storeId')) 'storeId': _storeIdProvider(),
      }),
    );
  }
}

class _ProxyTokens {
  const _ProxyTokens(this.idToken, this.appCheckToken);

  final String idToken;
  final String appCheckToken;
}
