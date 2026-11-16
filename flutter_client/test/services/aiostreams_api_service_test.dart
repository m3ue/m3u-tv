import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/api_client.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

const _credentials = UserCredentials(
  server: 'http://editor.test',
  username: 'viewer',
  password: 'secret',
);

const _actions = AIOStreamsActions(
  catalog: 'get_aiostreams_catalog',
  meta: 'get_aiostreams_meta',
  streams: 'get_aiostreams_streams',
);

final _catalogBody = <String, Object?>{
  'metas': [
    {'id': 'tt1234567', 'type': 'movie', 'name': 'A Movie'},
  ],
};

void main() {
  group('AIOStreamsActions.fromJson', () {
    test('reads all three actions', () {
      final actions = AIOStreamsActions.fromJson({
        'catalog': 'get_aiostreams_catalog',
        'meta': 'get_aiostreams_meta',
        'streams': 'get_aiostreams_streams',
      });

      expect(actions?.catalog, 'get_aiostreams_catalog');
      expect(actions?.meta, 'get_aiostreams_meta');
      expect(actions?.streams, 'get_aiostreams_streams');
    });

    test('is null when an action is missing or the key is absent', () {
      expect(AIOStreamsActions.fromJson({'catalog': 'x', 'meta': 'y'}), isNull);
      expect(AIOStreamsActions.fromJson(null), isNull);
    });
  });

  group('AIOStreamsApiService with player_api actions', () {
    test('fetches a catalog page over player_api.php', () async {
      final requests = <XtreamRequest>[];
      final xtream = XtreamService(
        transport: (request) async {
          requests.add(request);
          return jsonDecode(jsonEncode(_catalogBody));
        },
      )..replaceCredentialsOffline(_credentials);
      final service = AIOStreamsApiService(
        xtreamService: xtream,
        actionsFor: (_) => _actions,
        apiClient: ApiClient(
          client: MockClient((_) async => fail('path route used')),
        ),
      );

      final items = await service.getCatalog(
        7,
        'movie',
        'c54e3b0.tmdb.top',
        skip: 20,
      );

      expect(items.single.id, 'tt1234567');
      expect(requests.single.action, 'get_aiostreams_catalog');
      expect(requests.single.params, {
        'integration_id': '7',
        'type': 'movie',
        'catalog_id': 'c54e3b0.tmdb.top',
        'skip': '20',
      });
    });

    test('fetches streams with the item id', () async {
      final requests = <XtreamRequest>[];
      final xtream = XtreamService(
        transport: (request) async {
          requests.add(request);
          return <String, Object?>{
            'streams': [
              {
                'name': 'Source',
                'url': 'http://editor.test/movie/viewer/secret/aio-7-x.mkv',
              },
            ],
          };
        },
      )..replaceCredentialsOffline(_credentials);
      final service = AIOStreamsApiService(
        xtreamService: xtream,
        actionsFor: (_) => _actions,
      );

      final streams = await service.getStreams(7, 'series', 'tt7654321:1:2');

      expect(streams.single.url, contains('/movie/viewer/secret/aio-7-'));
      expect(requests.single.action, 'get_aiostreams_streams');
      expect(requests.single.params, {
        'integration_id': '7',
        'type': 'series',
        'id': 'tt7654321:1:2',
      });
    });

    test('returns an empty catalog when the action fails', () async {
      final xtream = XtreamService(
        transport: (request) async => throw XtreamHttpException(
          statusCode: 401,
          method: 'GET',
          uri: Uri.parse('http://editor.test/player_api.php'),
        ),
      )..replaceCredentialsOffline(_credentials);
      final service = AIOStreamsApiService(
        xtreamService: xtream,
        actionsFor: (_) => _actions,
      );

      expect(await service.getCatalog(7, 'movie', 'top'), isEmpty);
    });
  });

  group('AIOStreamsApiService without player_api actions', () {
    test('falls back to the path-style catalog route', () async {
      final uris = <Uri>[];
      final xtream = XtreamService(
        transport: (_) async => fail('player_api.php used'),
      )..replaceCredentialsOffline(_credentials);
      final service = AIOStreamsApiService(
        xtreamService: xtream,
        actionsFor: (_) => null,
        apiClient: ApiClient(
          client: MockClient((request) async {
            uris.add(request.url);
            return http.Response(jsonEncode(_catalogBody), 200);
          }),
        ),
      );

      final items = await service.getCatalog(7, 'movie', 'top', skip: 20);

      expect(items.single.id, 'tt1234567');
      expect(
        uris.single.path,
        '/viewer/secret/aiostreams/7/catalog/movie/top.json',
      );
      expect(uris.single.queryParameters, {'skip': '20'});
    });
  });
}
