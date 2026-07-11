import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pasella/services/twilio_proxy_client.dart';

void main() {
  test('proxy sends authenticated JSON without exposing Twilio credentials',
      () async {
    late http.Request captured;
    final client = TwilioProxyClient(
      idTokenProvider: () async => 'firebase-id-token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"success":true,"sid":"SM123"}', 201);
      }),
    );

    final response = await client.post({
      'action': 'send',
      'channel': 'sms',
      'to': '0648370009',
      'body': 'Pasella messaging test',
    });

    expect(response.statusCode, 201);
    expect(captured.url, TwilioProxyClient.endpoint);
    expect(captured.headers['authorization'], 'Bearer firebase-id-token');
    expect(captured.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(captured.body)['channel'], 'sms');
    expect(captured.body, isNot(contains('TWILIO_AUTH_TOKEN')));
  });

  test('proxy refuses requests when no merchant is signed in', () async {
    final client = TwilioProxyClient(
      idTokenProvider: () async => null,
      httpClient: MockClient((_) async => http.Response('', 500)),
    );

    expect(
      () => client.post({'action': 'send'}),
      throwsA(isA<StateError>()),
    );
  });
}
