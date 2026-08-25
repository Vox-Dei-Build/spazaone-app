import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:pasella/services/store_session.dart';

typedef SecureIdTokenProvider = Future<String?> Function();
typedef SecureAppCheckTokenProvider = Future<String?> Function();
typedef SecureRetryDelay = Future<void> Function(Duration duration);
typedef SecureStoreIdProvider = String Function();

class SecureFunctionClient {
  SecureFunctionClient({
    http.Client? httpClient,
    SecureIdTokenProvider? idTokenProvider,
    SecureAppCheckTokenProvider? appCheckTokenProvider,
    SecureIdTokenProvider? refreshedIdTokenProvider,
    SecureAppCheckTokenProvider? refreshedAppCheckTokenProvider,
    SecureRetryDelay? retryDelay,
    SecureStoreIdProvider? storeIdProvider,
  })  : _httpClient = httpClient ?? http.Client(),
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
            retryDelay ?? ((duration) => Future<void>.delayed(duration)),
        _storeIdProvider =
            storeIdProvider ?? (() => StoreSession.instance.storeId);

  final http.Client _httpClient;
  final SecureIdTokenProvider _idTokenProvider;
  final SecureAppCheckTokenProvider _appCheckTokenProvider;
  final SecureIdTokenProvider _refreshedIdTokenProvider;
  final SecureAppCheckTokenProvider _refreshedAppCheckTokenProvider;
  final SecureRetryDelay _retryDelay;
  final SecureStoreIdProvider _storeIdProvider;

  Future<http.Response> post(
    Uri endpoint,
    Map<String, dynamic> payload,
  ) async {
    _SecureFunctionTokens tokens;
    try {
      tokens = await _loadTokens(forceRefresh: false);
    } catch (_) {
      // Play Integrity/App Check can still be warming up immediately after a
      // cold start. Retry once with fresh credentials before failing closed.
      await _retryDelay(const Duration(milliseconds: 300));
      tokens = await _loadTokens(forceRefresh: true);
    }

    var response = await _send(endpoint, payload, tokens);
    if (_isCredentialFailure(response)) {
      // A cached credential can expire between acquisition and server-side
      // verification. Replay only authentication failures, never provider or
      // business-rule failures that could represent a financial attempt.
      tokens = await _loadTokens(forceRefresh: true);
      response = await _send(endpoint, payload, tokens);
    }
    return response;
  }

  Future<_SecureFunctionTokens> _loadTokens({
    required bool forceRefresh,
  }) async {
    final idToken =
        await (forceRefresh ? _refreshedIdTokenProvider() : _idTokenProvider());
    if (idToken == null || idToken.isEmpty) {
      throw StateError('A signed-in merchant is required.');
    }
    final appCheckToken = await (forceRefresh
        ? _refreshedAppCheckTokenProvider()
        : _appCheckTokenProvider());
    if (appCheckToken == null || appCheckToken.isEmpty) {
      throw StateError('App verification is required.');
    }

    return _SecureFunctionTokens(idToken, appCheckToken);
  }

  Future<http.Response> _send(
    Uri endpoint,
    Map<String, dynamic> payload,
    _SecureFunctionTokens tokens,
  ) {
    return _httpClient.post(
      endpoint,
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

  bool _isCredentialFailure(http.Response response) {
    if (response.statusCode != 401 && response.statusCode != 403) return false;
    try {
      final decoded = jsonDecode(response.body);
      final error = decoded is Map ? decoded['error']?.toString() : null;
      return error == 'Authentication required.' ||
          error == 'App verification required.' ||
          error == 'App verification failed.' ||
          error == 'Access denied.';
    } catch (_) {
      return false;
    }
  }
}

class _SecureFunctionTokens {
  const _SecureFunctionTokens(this.idToken, this.appCheckToken);

  final String idToken;
  final String appCheckToken;
}
