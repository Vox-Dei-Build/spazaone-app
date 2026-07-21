import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pasella/services/twilio_proxy_client.dart';

void main() {
  final endpoint = Uri.parse(
    'https://us-central1-demo-project.cloudfunctions.net/sendTwilioMessage',
  );
  test('proxy sends authenticated JSON without exposing Twilio credentials',
      () async {
    late http.Request captured;
    final client = TwilioProxyClient(
      idTokenProvider: () async => 'firebase-id-token',
      appCheckTokenProvider: () async => 'firebase-app-check-token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"success":true,"sid":"SM123"}', 201);
      }),
      endpoint: endpoint,
      storeIdProvider: () => 'store-a',
    );

    final response = await client.post({
      'action': 'send',
      'channel': 'sms',
      'to': '0648370009',
      'body': 'Pasella messaging test',
    });

    expect(response.statusCode, 201);
    expect(captured.url, endpoint);
    expect(captured.headers['authorization'], 'Bearer firebase-id-token');
    expect(
      captured.headers['x-firebase-appcheck'],
      'firebase-app-check-token',
    );
    expect(captured.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(captured.body)['channel'], 'sms');
    expect(captured.body, isNot(contains('TWILIO_AUTH_TOKEN')));
  });

  test('proxy refuses requests when no merchant is signed in', () async {
    final client = TwilioProxyClient(
      idTokenProvider: () async => null,
      appCheckTokenProvider: () async => 'firebase-app-check-token',
      httpClient: MockClient((_) async => http.Response('', 500)),
      endpoint: endpoint,
      storeIdProvider: () => 'store-a',
    );

    expect(
      () => client.post({'action': 'send'}),
      throwsA(isA<StateError>()),
    );
  });

  test('proxy refuses requests from an unattested app', () async {
    final client = TwilioProxyClient(
      idTokenProvider: () async => 'firebase-id-token',
      appCheckTokenProvider: () async => null,
      httpClient: MockClient((_) async => http.Response('', 500)),
      endpoint: endpoint,
      storeIdProvider: () => 'store-a',
    );

    expect(
      () => client.post({'action': 'send'}),
      throwsA(isA<StateError>()),
    );
  });

  test('retries cold-start token acquisition with forced refresh', () async {
    late http.Request captured;
    final client = TwilioProxyClient(
      idTokenProvider: () async => 'cached-id-token',
      appCheckTokenProvider: () async => null,
      refreshedIdTokenProvider: () async => 'refreshed-id-token',
      refreshedAppCheckTokenProvider: () async => 'refreshed-app-check-token',
      retryDelay: (_) async {},
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"success":true,"sid":"SM123"}', 201);
      }),
      endpoint: endpoint,
      storeIdProvider: () => 'store-a',
    );

    final response = await client.post({'action': 'send'});

    expect(response.statusCode, 201);
    expect(captured.headers['authorization'], 'Bearer refreshed-id-token');
    expect(
      captured.headers['x-firebase-appcheck'],
      'refreshed-app-check-token',
    );
  });

  test('refreshes credentials and retries once after 401', () async {
    final captured = <http.Request>[];
    final client = TwilioProxyClient(
      idTokenProvider: () async => 'cached-id-token',
      appCheckTokenProvider: () async => 'cached-app-check-token',
      refreshedIdTokenProvider: () async => 'refreshed-id-token',
      refreshedAppCheckTokenProvider: () async => 'refreshed-app-check-token',
      httpClient: MockClient((request) async {
        captured.add(request);
        if (captured.length == 1) return http.Response('', 401);
        return http.Response('{"success":true,"sid":"SM123"}', 201);
      }),
      endpoint: endpoint,
      storeIdProvider: () => 'store-a',
    );

    final response = await client.post({'action': 'send'});

    expect(response.statusCode, 201);
    expect(captured, hasLength(2));
    expect(captured.first.headers['authorization'], 'Bearer cached-id-token');
    expect(captured.last.headers['authorization'], 'Bearer refreshed-id-token');
    expect(
      captured.last.headers['x-firebase-appcheck'],
      'refreshed-app-check-token',
    );
  });
}
