import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3u_tv/services/api_client.dart';

void main() {
  final uri = Uri.parse('https://editor.example/api/tv/u/p/notifications');

  test('postJson sends a JSON body and decodes the reply', () async {
    late http.Request sent;
    final api = ApiClient(
      client: MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode({'id': 7}), 200);
      }),
    );

    final body = await api.postJson(uri, {'log': 'x'}, headers: {'x-a': '1'});

    expect(body, {'id': 7});
    expect(sent.method, 'POST');
    expect(sent.headers['content-type'], startsWith('application/json'));
    expect(sent.headers['x-a'], '1');
    expect(jsonDecode(sent.body), {'log': 'x'});
  });

  test('an empty body decodes to null', () async {
    final api = ApiClient(
      client: MockClient((_) async => http.Response('', 204)),
    );
    expect(await api.getJson(uri), isNull);
  });

  test('an error status throws ApiException carrying the body', () async {
    final api = ApiClient(
      client: MockClient((_) async => http.Response('nope', 503)),
    );
    await expectLater(
      api.getJson(uri),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having((e) => e.body, 'body', 'nope')
            .having((e) => e.uri, 'uri', uri),
      ),
    );
  });

  test('send returns error responses without throwing', () async {
    final api = ApiClient(
      client: MockClient(
        (_) async => http.Response('{"error":"authorization_pending"}', 400),
      ),
    );
    final response = await api.send('POST', uri, json: const {});
    expect(response.isError, isTrue);
    expect(await response.json(), {'error': 'authorization_pending'});
  });

  test('a stalled server times out', () async {
    final api = ApiClient(
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(api.getJson(uri), throwsA(isA<TimeoutException>()));
  });
}
