import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pasella/services/secure_function_client.dart';

void main() {
  final endpoint = Uri.parse(
    'https://us-central1-demo-project.cloudfunctions.net/secureAction',
  );

  test('sends authenticated JSON scoped to the active store', () async {
    late http.Request captured;
    final client = SecureFunctionClient(
      idTokenProvider: () async => 'cached-id-token',
      appCheckTokenProvider: () async => 'cached-app-check-token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"success":true}', 200);
      }),
      storeIdProvider: () => 'store-a',
    );

    final response = await client.post(endpoint, {'merchantId': 'store-a'});

    expect(response.statusCode, 200);
    expect(captured.headers['authorization'], 'Bearer cached-id-token');
    expect(
      captured.headers['x-firebase-appcheck'],
      'cached-app-check-token',
    );
    expect(jsonDecode(captured.body), {
      'merchantId': 'store-a',
      'storeId': 'store-a',
    });
  });

  test('retries cold-start token acquisition with forced refresh', () async {
    late http.Request captured;
    var delayCalls = 0;
    final client = SecureFunctionClient(
      idTokenProvider: () async => 'cached-id-token',
      appCheckTokenProvider: () async => null,
      refreshedIdTokenProvider: () async => 'refreshed-id-token',
      refreshedAppCheckTokenProvider: () async => 'refreshed-app-check-token',
      retryDelay: (_) async => delayCalls += 1,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"success":true}', 200);
      }),
      storeIdProvider: () => 'store-a',
    );

    final result = await client.postWithDiagnostics(endpoint, const {});
    final response = result.response;

    expect(response.statusCode, 200);
    expect(result.retryOutcome, 'credentials_refreshed');
    expect(delayCalls, 1);
    expect(captured.headers['authorization'], 'Bearer refreshed-id-token');
    expect(
      captured.headers['x-firebase-appcheck'],
      'refreshed-app-check-token',
    );
  });

  test('refreshes credentials once after an App Check rejection', () async {
    final captured = <http.Request>[];
    final client = SecureFunctionClient(
      idTokenProvider: () async => 'cached-id-token',
      appCheckTokenProvider: () async => 'cached-app-check-token',
      refreshedIdTokenProvider: () async => 'refreshed-id-token',
      refreshedAppCheckTokenProvider: () async => 'refreshed-app-check-token',
      httpClient: MockClient((request) async {
        captured.add(request);
        if (captured.length == 1) {
          return http.Response('{"error":"App verification failed."}', 401);
        }
        return http.Response('{"success":true}', 200);
      }),
      storeIdProvider: () => 'store-a',
    );

    final result = await client.postWithDiagnostics(endpoint, const {});
    final response = result.response;

    expect(response.statusCode, 200);
    expect(result.retryOutcome, 'recovered');
    expect(captured, hasLength(2));
    expect(captured.first.headers['authorization'], 'Bearer cached-id-token');
    expect(captured.last.headers['authorization'], 'Bearer refreshed-id-token');
    expect(
      captured.last.headers['x-firebase-appcheck'],
      'refreshed-app-check-token',
    );
  });

  test('never replays a financial request after a business-rule failure',
      () async {
    var requests = 0;
    var refreshes = 0;
    final client = SecureFunctionClient(
      idTokenProvider: () async => 'cached-id-token',
      appCheckTokenProvider: () async => 'cached-app-check-token',
      refreshedIdTokenProvider: () async {
        refreshes += 1;
        return 'refreshed-id-token';
      },
      refreshedAppCheckTokenProvider: () async {
        refreshes += 1;
        return 'refreshed-app-check-token';
      },
      httpClient: MockClient((request) async {
        requests += 1;
        return http.Response(
          '{"error":"Your settlement-verification request was sent to Spaza One for approval."}',
          403,
        );
      }),
      storeIdProvider: () => 'store-a',
    );

    final response = await client.post(endpoint, const {});

    expect(response.statusCode, 403);
    expect(requests, 1);
    expect(refreshes, 0);
  });
}
