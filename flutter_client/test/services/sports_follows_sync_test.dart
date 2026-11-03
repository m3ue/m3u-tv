import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/sports_settings.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

const _credentials = UserCredentials(
  server: 'https://fixture.example',
  username: 'fixture-user',
  password: 'fixture-password',
);

const _leafs = SportsTeam(
  leagueId: 'hockey/nhl',
  id: '21',
  displayName: 'Toronto Maple Leafs',
  shortName: 'Maple Leafs',
  nickname: 'Maple Leafs',
  abbreviation: 'TOR',
);

const _ducks = SportsTeam(
  leagueId: 'hockey/nhl',
  id: '1',
  displayName: 'Anaheim Ducks',
  shortName: 'Ducks',
  nickname: 'Ducks',
  abbreviation: 'ANA',
);

const _kid = Viewer(id: 2, ulid: 'viewer-kid', name: 'Kid', isAdmin: false);

Map<String, Object?> _follow(SportsTeam team) => {
  'team_key': team.key,
  'league_id': team.leagueId,
  'team_id': team.id,
  'name': team.displayName,
  'logo': 'https://fixture.example/logo-proxy/${team.id}.png',
};

/// An editor with Sports on (or off), one admin viewer and one child, and
/// per-viewer follows; every request is recorded.
class _SportsEditor {
  _SportsEditor({this.sports = true, this.adminIsAdmin = true});

  final bool sports;
  final bool adminIsAdmin;
  final List<XtreamRequest> requests = [];
  final Map<String, List<Map<String, Object?>>> followsByViewer = {};
  String? blockedFollowsViewer;
  final blockedFollowsStarted = Completer<void>();
  final releaseBlockedFollows = Completer<void>();

  Future<Object?> call(XtreamRequest request) async {
    final action = request.action ?? 'auth';
    requests.add(request);
    switch (action) {
      case 'auth':
        return {
          'user_info': {'auth': 1, 'status': 'Active'},
          'm3u_editor': {
            'version': '0.14.0',
            'features': [if (sports) 'sports'],
            if (sports)
              'sports': {
                'api_version': 1,
                'actions': {
                  'fixtures': 'get_sports_fixtures',
                  'teams': 'get_sports_teams',
                  'follows': 'get_sports_follows',
                  'toggle_follow': 'toggle_sports_follow',
                  'sync_follows': 'sync_sports_follows',
                },
                'leagues': [
                  {'id': 'hockey/nhl', 'name': 'NHL', 'abbreviation': 'NHL'},
                ],
              },
          },
        };
      case 'get_viewers':
        return [
          {
            'id': 1,
            'ulid': 'viewer-admin',
            'name': 'Admin',
            'is_admin': adminIsAdmin,
          },
          {'id': 2, 'ulid': 'viewer-kid', 'name': 'Kid', 'is_admin': false},
        ];
      case 'get_sports_follows':
        final viewer = '${request.params['viewer_id']}';
        if (viewer == blockedFollowsViewer) {
          blockedFollowsStarted.complete();
          await releaseBlockedFollows.future;
        }
        return {'follows': followsByViewer[viewer] ?? const []};
      case 'sync_sports_follows':
        final viewer = '${request.body['viewer_id']}';
        final merged = [
          ...?followsByViewer[viewer],
          for (final item in request.body['follows']! as List)
            {..._follow(_leafs), ...(item as Map<String, Object?>)},
        ];
        followsByViewer[viewer] = merged;
        return {'follows': merged};
      case 'toggle_sports_follow':
        return {'follows': const <Object?>[]};
      case 'get_favorites':
      case 'sync_favorites':
      case 'get_live_categories':
      case 'get_vod_categories':
      case 'get_series_categories':
      case 'get_live_streams':
      case 'get_vod_streams':
      case 'get_series':
      case 'get_recently_watched':
        return const <Object?>[];
      case 'get_epg_batch':
        return const <String, Object?>{};
      default:
        throw StateError('No fixture for $action');
    }
  }

  Iterable<XtreamRequest> sent(String action) =>
      requests.where((request) => request.action == action);
}

AppStateController _controller(_SportsEditor editor, SportsSettings settings) {
  final memory = <String, Object?>{};
  return AppStateController(
    xtreamService: XtreamService(
      transport: editor.call,
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
    sportsSettings: settings,
  );
}

Future<AppStateController> _connect(
  _SportsEditor editor,
  SportsSettings settings,
) async {
  final controller = _controller(editor, settings);
  addTearDown(controller.dispose);
  expect(await controller.connectXtream(_credentials), isTrue);
  await pumpEventQueue();
  return controller;
}

void main() {
  test(
    "an admin's first sync merges this device's follows into the account",
    () async {
      final settings = SportsSettings();
      await settings.toggleFollow(_leafs);
      final editor = _SportsEditor()
        ..followsByViewer['viewer-admin'] = [_follow(_ducks)];

      await _connect(editor, settings);

      final sync = editor.sent('sync_sports_follows').single;
      expect(sync.body['viewer_id'], 'viewer-admin');
      expect(sync.body['follows'], [
        {'team_key': 'hockey/nhl:21', 'name': 'Toronto Maple Leafs'},
      ]);
      expect(settings.followedTeamKeys, {'hockey/nhl:1', 'hockey/nhl:21'});
      expect(
        settings.followedTeams.first.logoUrl,
        'https://fixture.example/logo-proxy/1.png',
      );
    },
  );

  test('after the first sync the server is authoritative', () async {
    final settings = SportsSettings();
    await settings.toggleFollow(_leafs);
    final editor = _SportsEditor();
    await _connect(editor, settings);

    // Removed on another device since.
    editor.followsByViewer['viewer-admin'] = [_follow(_ducks)];
    editor.requests.clear();
    await _connect(editor, settings);

    expect(editor.sent('sync_sports_follows'), isEmpty);
    expect(editor.sent('get_sports_follows'), isNotEmpty);
    expect(settings.followedTeamKeys, {'hockey/nhl:1'});
  });

  test('a child viewer only ever pulls its own follows', () async {
    final settings = SportsSettings();
    await settings.toggleFollow(_leafs);
    final editor = _SportsEditor(adminIsAdmin: false);

    await _connect(editor, settings);

    expect(editor.sent('sync_sports_follows'), isEmpty);
    expect(settings.followedTeams, isEmpty);
  });

  test('a follow from the UI is pushed for the active viewer', () async {
    final settings = SportsSettings();
    final editor = _SportsEditor();
    await _connect(editor, settings);

    await settings.toggleFollow(_ducks);
    await pumpEventQueue();
    await settings.toggleFollow(_ducks);
    await pumpEventQueue();

    final pushes = editor.sent('toggle_sports_follow').toList();
    expect(pushes.map((request) => request.body['followed']), [
      'true',
      'false',
    ]);
    expect(pushes.first.body, containsPair('team_key', 'hockey/nhl:1'));
    expect(pushes.first.body, containsPair('viewer_id', 'viewer-admin'));
  });

  test('without the sports feature follows stay local and unsent', () async {
    final settings = SportsSettings();
    await settings.toggleFollow(_leafs);
    final editor = _SportsEditor(sports: false);

    await _connect(editor, settings);
    await settings.toggleFollow(_ducks);
    await pumpEventQueue();

    expect(
      editor.requests.where(
        (request) => '${request.action}'.contains('sports'),
      ),
      isEmpty,
    );
    expect(settings.followedTeamKeys, {'hockey/nhl:21', 'hockey/nhl:1'});
  });

  test("a viewer switch discards the previous viewer's late reply", () async {
    final settings = SportsSettings();
    final editor = _SportsEditor()
      ..followsByViewer['viewer-admin'] = [_follow(_leafs)]
      ..followsByViewer['viewer-kid'] = [_follow(_ducks)];
    final controller = await _connect(editor, settings);
    expect(settings.followedTeamKeys, {'hockey/nhl:21'});

    // The admin's next pull stalls; meanwhile the kid takes over.
    editor.blockedFollowsViewer = 'viewer-admin';
    final refresh = controller.connectXtream(_credentials);
    await editor.blockedFollowsStarted.future;
    await controller.switchViewer(_kid);
    await pumpEventQueue();
    editor.releaseBlockedFollows.complete();
    await refresh;
    await pumpEventQueue();

    expect(controller.activeViewer?.ulid, 'viewer-kid');
    expect(settings.followedTeamKeys, {'hockey/nhl:1'});
  });
}
