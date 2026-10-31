import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/tv_notification_store.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_http_transport_common.dart';
import 'package:m3u_tv/services/xtream_service.dart';

const _credentials = UserCredentials(
  server: 'https://editor.example',
  username: 'guest',
  password: 'secret',
);

/// Contract coverage for the `request_*` actions m3u-editor advertises under
/// `m3u_editor.requests.actions` (#195). Error responses go through the real
/// [handleXtreamResponse] so the tests see the same 4xx/5xx shape production
/// does, not a 200 with an error body.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('request action parameters and responses', () {
    late _ContractTransport transport;
    late XtreamService service;

    setUp(() async {
      transport = _ContractTransport();
      service = XtreamService(
        transport: transport.call,
        cache: CacheService(memory: <String, Object?>{}),
      );
      await service.authenticate(_credentials);
    });

    test('request_search sends query, type and paging as GET params', () async {
      transport.respond('request_search', {
        'results': [
          {
            'type': 'movie',
            'external_id': '603',
            'integration_id': 7,
            'integration_name': 'Radarr',
            'title': 'The Matrix',
            'year': '1999',
            'already_available': true,
          },
        ],
      });

      final results = await service.searchContentRequests(
        'matrix',
        type: 'movie',
        page: 2,
        perPage: 10,
      );

      final request = transport.last('request_search');
      expect(request.method, 'GET');
      expect(request.params, {
        'query': 'matrix',
        'type': 'movie',
        'page': '2',
        'per_page': '10',
      });
      expect(results.single.externalId, '603');
      expect(results.single.integrationId, 7);
      expect(results.single.integrationName, 'Radarr');
      expect(results.single.alreadyAvailable, isTrue);
    });

    test('request_search omits type when searching every type', () async {
      transport.respond('request_search', {'results': const <Object?>[]});

      expect(await service.searchContentRequests('matrix'), isEmpty);
      expect(
        transport.last('request_search').params.containsKey('type'),
        isFalse,
      );
    });

    test('request_submit POSTs the selection and parses the request', () async {
      transport.respond('request_submit', {
        'request': _summaryJson(id: 41, status: 'pending_approval'),
      });

      final summary = await service.submitContentRequest(
        type: 'series',
        integrationId: 3,
        externalId: '1399',
        seasons: [1, 2],
      );

      final request = transport.last('request_submit');
      expect(request.method, 'POST');
      expect(request.body, {
        'type': 'series',
        'integration_id': '3',
        'external_id': '1399',
        'seasons': [1, 2],
      });
      expect(summary.id, 41);
      expect(summary.status, MediaRequestStatus.pendingApproval);
    });

    test(
      'request_submit leaves seasons out for a whole-series request',
      () async {
        transport.respond('request_submit', {
          'request': _summaryJson(id: 42, status: 'approved'),
        });

        await service.submitContentRequest(
          type: 'series',
          integrationId: 3,
          externalId: '1399',
        );

        expect(
          transport.last('request_submit').body.containsKey('seasons'),
          isFalse,
        );
      },
    );

    test('request_history sends paging and parses every request', () async {
      transport.respond('request_history', {
        'requests': [
          _summaryJson(id: 1, status: 'downloading'),
          _summaryJson(id: 2, status: 'imported'),
          _summaryJson(id: 3, status: 'some_future_status'),
        ],
      });

      final requests = await service.getMediaRequests(page: 3, perPage: 25);

      final request = transport.last('request_history');
      expect(request.method, 'GET');
      expect(request.params, {'page': '3', 'per_page': '25'});
      expect(requests.map((r) => r.status), [
        MediaRequestStatus.approved,
        MediaRequestStatus.completed,
        MediaRequestStatus.unknown,
      ]);
    });

    test('request_status sends the request id and parses progress', () async {
      transport.respond('request_status', {
        'request': {
          ..._summaryJson(id: 9, status: 'downloading'),
          'progress': 55,
        },
      });

      final summary = await service.getMediaRequestStatus(9);

      final request = transport.last('request_status');
      expect(request.method, 'GET');
      expect(request.params, {'request_id': '9'});
      expect(summary.progress, 55);
    });

    test('request_dismiss POSTs the request id', () async {
      transport.respond('request_dismiss', {'dismissed': true});

      await service.dismissMediaRequest(9);

      final request = transport.last('request_dismiss');
      expect(request.method, 'POST');
      expect(request.body, {'request_id': '9'});
    });
  });

  group('documented error envelopes', () {
    late _ContractTransport transport;
    late XtreamService service;

    setUp(() async {
      transport = _ContractTransport();
      service = XtreamService(
        transport: transport.call,
        cache: CacheService(memory: <String, Object?>{}),
      );
      await service.authenticate(_credentials);
    });

    final cases =
        <(String, String, int, Future<Object?> Function(XtreamService))>[
          (
            'request_submit',
            'already_requested',
            409,
            (s) => s.submitContentRequest(
              type: 'movie',
              integrationId: 1,
              externalId: '603',
            ),
          ),
          (
            'request_submit',
            'already_available',
            409,
            (s) => s.submitContentRequest(
              type: 'movie',
              integrationId: 1,
              externalId: '603',
            ),
          ),
          (
            'request_submit',
            'provider_unavailable',
            503,
            (s) => s.submitContentRequest(
              type: 'movie',
              integrationId: 1,
              externalId: '603',
            ),
          ),
          (
            'request_search',
            'providers_unavailable',
            503,
            (s) => s.searchContentRequests('matrix'),
          ),
          (
            'request_search',
            'rate_limited',
            429,
            (s) => s.searchContentRequests('matrix'),
          ),
          (
            'request_history',
            'request_access_denied',
            403,
            (s) => s.getMediaRequests(),
          ),
          (
            'request_status',
            'request_not_found',
            404,
            (s) => s.getMediaRequestStatus(9),
          ),
          (
            'request_dismiss',
            'request_not_dismissible',
            422,
            (s) => s.dismissMediaRequest(9),
          ),
        ];

    for (final (action, code, status, call) in cases) {
      test(
        '$action maps HTTP $status $code to XtreamRequestException',
        () async {
          transport.fail(
            action,
            status: status,
            code: code,
            message: 'From server',
          );

          await expectLater(
            call(service),
            throwsA(
              isA<XtreamRequestException>()
                  .having((e) => e.code, 'code', code)
                  .having((e) => e.message, 'message', 'From server'),
            ),
          );
        },
      );
    }

    test('an error envelope sent with HTTP 200 is still raised', () async {
      transport.respond(
        'request_search',
        null,
        error: {
          'code': 'rate_limited',
          'message': 'Slow down',
        },
      );

      await expectLater(
        service.searchContentRequests('matrix'),
        throwsA(
          isA<XtreamRequestException>().having(
            (e) => e.code,
            'code',
            'rate_limited',
          ),
        ),
      );
    });

    test(
      'an unknown error code degrades to its raw code and message',
      () async {
        transport.fail(
          'request_submit',
          status: 422,
          code: 'brand_new_code',
          message: 'Something new went wrong',
        );

        await expectLater(
          service.submitContentRequest(
            type: 'movie',
            integrationId: 1,
            externalId: '603',
          ),
          throwsA(
            isA<XtreamRequestException>()
                .having((e) => e.code, 'code', 'brand_new_code')
                .having(
                  (e) => e.message,
                  'message',
                  'Something new went wrong',
                ),
          ),
        );
      },
    );

    test(
      'an error without code or message falls back to safe defaults',
      () async {
        transport.failRaw(
          'request_search',
          status: 422,
          body: jsonEncode({'api_version': 1, 'error': <String, Object?>{}}),
        );

        await expectLater(
          service.searchContentRequests('matrix'),
          throwsA(
            isA<XtreamRequestException>()
                .having((e) => e.code, 'code', 'unknown')
                .having(
                  (e) => e.message,
                  'message',
                  'The request could not be completed.',
                ),
          ),
        );
      },
    );

    test(
      'an error without the envelope stays an XtreamHttpException',
      () async {
        transport.failRaw(
          'request_search',
          status: 500,
          body: '<!DOCTYPE html><html>Server Error</html>',
        );

        await expectLater(
          service.searchContentRequests('matrix'),
          throwsA(
            isA<XtreamHttpException>().having(
              (e) => e.statusCode,
              'statusCode',
              500,
            ),
          ),
        );
      },
    );

    test('the request error message never carries credentials', () async {
      transport.fail(
        'request_submit',
        status: 409,
        code: 'already_requested',
        message: 'This title has already been requested.',
      );

      try {
        await service.submitContentRequest(
          type: 'movie',
          integrationId: 1,
          externalId: '603',
        );
        fail('expected XtreamRequestException');
      } on XtreamRequestException catch (error) {
        expect(error.toString(), isNot(contains(_credentials.password)));
        expect(error.toString(), isNot(contains(_credentials.username)));
      }
    });
  });

  group('feature gating', () {
    test(
      'a session without the requests feature never calls request actions',
      () async {
        final transport = _ContractTransport(features: const <String>[]);
        final controller = _controller(transport);
        addTearDown(controller.dispose);

        expect(await controller.connectXtream(_credentials), isTrue);
        expect(controller.hasRequestsFeature, isFalse);
        await controller.refreshMediaRequests();

        expect(
          transport.requests.where(
            (r) => (r.action ?? '').startsWith('request_'),
          ),
          isEmpty,
        );
      },
    );

    test('a session with the requests feature loads request_history', () async {
      final transport = _ContractTransport()
        ..respond('request_history', {'requests': const <Object?>[]});
      final controller = _controller(transport);
      addTearDown(controller.dispose);

      expect(await controller.connectXtream(_credentials), isTrue);
      expect(controller.hasRequestsFeature, isTrue);
      await controller.refreshMediaRequests();

      expect(
        transport.requests.map((r) => r.action),
        contains('request_history'),
      );
    });
  });
}

Map<String, Object?> _summaryJson({required int id, required String status}) =>
    <String, Object?>{
      'id': id,
      'type': 'movie',
      'title': 'Request $id',
      'status': status,
      'integration_id': 7,
      'integration_name': 'Radarr',
    };

class _ContractTransport {
  _ContractTransport({this.features = const <String>['requests']});

  final List<String> features;
  final requests = <XtreamRequest>[];
  final _handlers = <String, Future<Object?> Function(XtreamRequest)>{};

  XtreamRequest last(String action) =>
      requests.lastWhere((request) => request.action == action);

  void respond(
    String action,
    Map<String, Object?>? data, {
    Map<String, Object?>? error,
  }) {
    _handlers[action] = (_) async => <String, Object?>{
      'api_version': 1,
      'data': ?data,
      'error': ?error,
    };
  }

  void fail(
    String action, {
    required int status,
    required String code,
    required String message,
  }) => failRaw(
    action,
    status: status,
    body: jsonEncode({
      'api_version': 1,
      'error': {'code': code, 'message': message},
    }),
  );

  void failRaw(String action, {required int status, required String body}) {
    _handlers[action] = (request) => handleXtreamResponse(
      request: request,
      uri: Uri.parse(
        '${request.credentials.server}/player_api.php',
      ).replace(queryParameters: {'action': action}),
      statusCode: status,
      reasonPhrase: null,
      bytes: Uint8List.fromList(utf8.encode(body)),
    );
  }

  Future<Object?> call(XtreamRequest request) async {
    requests.add(request);
    final action = request.action;
    if (action == null) {
      return <String, Object?>{
        'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
        'server_info': <String, Object?>{'timezone': 'UTC'},
        'm3u_editor': <String, Object?>{
          'version': '0.13.7',
          'features': features,
        },
      };
    }
    final handler = _handlers[action];
    if (handler != null) return handler(request);
    return switch (action) {
      'get_live_categories' ||
      'get_vod_categories' ||
      'get_series_categories' ||
      'get_live_streams' ||
      'get_vod_streams' ||
      'get_series' ||
      'get_viewers' => const <Object?>[],
      _ => throw StateError('No fixture for $action'),
    };
  }
}

AppStateController _controller(_ContractTransport transport) {
  final memory = <String, Object?>{};
  return AppStateController(
    xtreamService: XtreamService(
      transport: transport.call,
      cache: CacheService(memory: <String, Object?>{}),
    ),
    secureStorage: InMemorySecureStorage(),
    cacheService: CacheService(memory: <String, Object?>{}),
    favoritesService: FavoritesService(memory: memory),
    vodFavoritesService: FavoritesService(memory: memory, namespace: 'vod'),
    seriesFavoritesService: FavoritesService(
      memory: memory,
      namespace: 'series',
    ),
    resumeService: ResumeService(memory: memory),
    viewerService: ViewerService(memory: memory),
    tvNotificationService: _NotificationService(),
    tvNotificationStore: TvNotificationStore(memory: memory),
    reverbService: _NoopReverbService(),
  );
}

class _NotificationService extends TvNotificationService {
  @override
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async => const (
    TvPlaylistSession(
      notifiableId: 1,
      notifiableType: 'playlist',
      isAdmin: false,
      channelName: '',
      reverb: ReverbConfig(host: '', port: 0, scheme: 'wss', appKey: ''),
    ),
    <TvNotificationItem>[],
  );
}

class _NoopReverbService extends ReverbService {
  @override
  Future<void> disconnect() async {}
}
