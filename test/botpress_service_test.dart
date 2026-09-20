import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pasella/services/botpress_service.dart';
import 'package:pasella/services/secure_function_client.dart';

SecureFunctionClient _client(MockClient httpClient) => SecureFunctionClient(
      httpClient: httpClient,
      idTokenProvider: () async => 'cached-id-token',
      appCheckTokenProvider: () async => 'cached-app-check-token',
      refreshedIdTokenProvider: () async => 'fresh-id-token',
      refreshedAppCheckTokenProvider: () async => 'fresh-app-check-token',
      retryDelay: (_) async {},
      storeIdProvider: () => 'store-a',
    );

Map<String, dynamic> _message(String id) => {
      'id': id,
      'payload': {'type': 'text', 'text': 'Hello'},
      'createdAt': '2026-09-20T13:20:00.000Z',
      'direction': 'outgoing',
      'tags': <String, dynamic>{},
    };

void main() {
  test('keeps valid Botpress messages when another record is malformed',
      () async {
    final service = BotpressService.forTesting(
      _client(MockClient((_) async => http.Response(
            jsonEncode({
              'state': 'ok',
              'messages': [_message('valid-1'), 42],
              'diagnostic': {'skippedMessageCount': 1},
            }),
            200,
          ))),
    );

    final result =
        await service.fetchBotpressMessages(customerId: 'customer-a');

    expect(result.messages, hasLength(1));
    expect(result.messages.single['id'], 'valid-1');
    expect(result.warningCode, 'BOTPRESS_MESSAGES_PARTIAL');
    expect(result.skippedMessageCount, 2);
    service.dispose();
  });

  test('maps malformed top-level contracts to a response warning', () async {
    final service = BotpressService.forTesting(
      _client(MockClient((_) async => http.Response('[]', 200))),
    );

    final result =
        await service.fetchBotpressMessages(customerId: 'customer-a');

    expect(result.messages, isEmpty);
    expect(result.warning?.code, 'BOTPRESS_RESPONSE_INVALID');
    expect(result.warning?.stage, 'response');
    service.dispose();
  });

  test('classifies network failures separately from response failures',
      () async {
    final service = BotpressService.forTesting(
      _client(MockClient((_) async => throw Exception('network detail'))),
    );

    final result =
        await service.fetchBotpressMessages(customerId: 'customer-a');

    expect(result.warning?.code, 'BOTPRESS_TRANSPORT_UNAVAILABLE');
    expect(result.warning?.stage, 'transport');
    expect(result.warning?.message, isNot(contains('network detail')));
    service.dispose();
  });

  test('refreshes App Check once and clears the warning after recovery',
      () async {
    final requests = <http.Request>[];
    final service = BotpressService.forTesting(
      _client(MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) {
          return http.Response('{"error":"App verification failed."}', 401);
        }
        return http.Response(
          jsonEncode({
            'state': 'ok',
            'messages': [_message('recovered-1')],
            'diagnostic': {'skippedMessageCount': 0},
          }),
          200,
        );
      })),
    );

    final result =
        await service.fetchBotpressMessages(customerId: 'customer-a');

    expect(requests, hasLength(2));
    expect(requests.first.headers['x-firebase-appcheck'],
        'cached-app-check-token');
    expect(
        requests.last.headers['x-firebase-appcheck'], 'fresh-app-check-token');
    expect(result.messages, hasLength(1));
    expect(result.warning, isNull);
    service.dispose();
  });

  test('returns a retryable warning for total provider failure', () async {
    final service = BotpressService.forTesting(
      _client(MockClient((_) async => http.Response(
            jsonEncode({
              'state': 'error',
              'error': 'Conversation service unavailable.',
              'diagnostic': {'code': 'BOTPRESS_PROVIDER_UNAVAILABLE'},
            }),
            502,
          ))),
    );

    final result =
        await service.fetchBotpressMessages(customerId: 'customer-a');

    expect(result.messages, isEmpty);
    expect(result.warning?.code, 'BOTPRESS_PROVIDER_UNAVAILABLE');
    expect(result.warning?.stage, 'transport');
    service.dispose();
  });

  test('distinguishes authentication from App Check rejection', () async {
    final service = BotpressService.forTesting(
      _client(MockClient((_) async => http.Response(
            jsonEncode({
              'error': 'Authentication required.',
              'code': 'AUTHENTICATION_REQUIRED',
            }),
            401,
          ))),
    );

    final result =
        await service.fetchBotpressMessages(customerId: 'customer-a');

    expect(result.warning?.code, 'AUTHENTICATION_REQUIRED');
    expect(result.warning?.stage, 'credentials');
    expect(result.warning?.message, contains('Sign in again'));
    expect(result.warning?.message, isNot(contains('verified')));
    service.dispose();
  });

  test('a later warning retry clears the warning and restores history',
      () async {
    var calls = 0;
    final service = BotpressService.forTesting(
      _client(MockClient((_) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({
              'state': 'error',
              'diagnostic': {'code': 'BOTPRESS_PROVIDER_UNAVAILABLE'},
            }),
            502,
          );
        }
        return http.Response(
          jsonEncode({
            'state': 'ok',
            'messages': [_message('available-1')],
          }),
          200,
        );
      })),
    );

    final failed =
        await service.fetchBotpressMessages(customerId: 'customer-a');
    final recovered =
        await service.fetchBotpressMessages(customerId: 'customer-a');

    expect(failed.warning?.code, 'BOTPRESS_PROVIDER_UNAVAILABLE');
    expect(recovered.warning, isNull);
    expect(recovered.messages, hasLength(1));
    service.dispose();
  });

  test('tolerates unexpected nested card, title and list values', () async {
    final service = BotpressService.forTesting(
      _client(MockClient((_) async => http.Response(
            jsonEncode({
              'state': 'ok',
              'messages': [
                {
                  'id': 'nested-1',
                  'payload': {
                    'type': 'carousel',
                    'items': [
                      {
                        'title': {'unexpected': true},
                        'subtitle': 42,
                        'actions': 'not-a-list',
                      },
                      'not-a-card',
                    ],
                  },
                  'tags': ['not-a-map'],
                },
              ],
            }),
            200,
          ))),
    );

    final result =
        await service.fetchBotpressMessages(customerId: 'customer-a');

    expect(result.messages, hasLength(1));
    expect(result.warning, isNull);
    service.dispose();
  });
}
