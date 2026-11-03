import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/sports_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

const _credentials = UserCredentials(
  server: 'https://editor.example',
  username: 'user',
  password: 'pass',
);

Map<String, Object?> _sportsPayload() => {
  'api_version': 1,
  'actions': {'fixtures': 'get_sports_fixtures'},
  'max_range_days': 14,
  'leagues': [
    {
      'id': 'hockey/nhl',
      'name': 'NHL',
      'abbreviation': 'NHL',
      'soccer_style': false,
      'default': true,
    },
    {
      'id': 'soccer/eng.1',
      'name': 'Premier League',
      'abbreviation': 'EPL',
      'soccer_style': true,
      'default': false,
    },
  ],
};

Map<String, Object?> _side(String id, String name, String nickname) => {
  'score': '2',
  'winner': false,
  'team': {
    'id': id,
    'display_name': name,
    'short_name': nickname,
    'nickname': nickname,
    'abbreviation': id.toUpperCase(),
    'logo': 'https://editor.example/logo-proxy/abc/$id.png?p=photo',
    'color': '003e7e',
    'alternate_color': null,
  },
};

Map<String, Object?> _fixture(String id, String start, {String? league}) => {
  'id': id,
  'league_id': league ?? 'hockey/nhl',
  'start': start,
  'state': 'live',
  'status_detail': '1st - 15:00',
  'name': 'Utah Mammoth at Toronto Maple Leafs',
  'broadcasts': ['ESPN+'],
  'home': _side('tor', 'Toronto Maple Leafs', 'Maple Leafs'),
  'away': _side('uta', 'Utah Mammoth', 'Mammoth'),
};

/// An authenticated XtreamService whose editor advertises [sports] and
/// answers fixtures requests with [fixtures], recording each request.
Future<(XtreamService, List<XtreamRequest>)> _xtream({
  Map<String, Object?>? sports,
  List<Object?> fixtures = const [],
}) async {
  final requests = <XtreamRequest>[];
  final service = XtreamService(
    transport: (request) async {
      requests.add(request);
      if (request.action == null) {
        return {
          'user_info': {'auth': 1, 'status': 'Active'},
          'server_info': {'timezone': 'UTC'},
          'm3u_editor': {
            'version': '0.14.0',
            'features': [if (sports != null) 'sports'],
            'sports': ?sports,
          },
        };
      }
      return {'fixtures': fixtures};
    },
  );
  final auth = await service.authenticate(_credentials);
  expect(auth.hasSports, sports != null);
  return (service, requests);
}

void main() {
  test('reads the sports capability from the auth payload', () async {
    final service = XtreamService(
      transport: (_) async => {
        'user_info': {'auth': 1, 'status': 'Active'},
        'server_info': {'timezone': 'UTC'},
        'm3u_editor': {
          'version': '0.14.0',
          'features': ['sports'],
          'sports': _sportsPayload(),
        },
      },
    );
    final sports = (await service.authenticate(_credentials)).sports!;
    expect(sports.fixturesAction, 'get_sports_fixtures');
    expect(sports.leagues.map((league) => league.id), [
      'hockey/nhl',
      'soccer/eng.1',
    ]);
    expect(sports.leagueById('soccer/eng.1')!.soccerStyle, isTrue);
    expect(sports.leagueById('hockey/nhl')!.isDefault, isTrue);
  });

  test('without the feature there is no sports capability', () async {
    await _xtream();
  });

  test(
    'asks the editor for the leagues and range, and maps the reply',
    () async {
      final (xtream, requests) = await _xtream(
        sports: _sportsPayload(),
        fixtures: [
          _fixture('2', '2026-11-04T02:00:00Z'),
          _fixture('1', '2026-11-04T00:00:00Z'),
          // A league the capability doesn't list.
          _fixture('3', '2026-11-04T00:00:00Z', league: 'other/league'),
          {'id': 'no-start'},
        ],
      );
      final capability = SportsCapability.fromJson(_sportsPayload());
      final from = DateTime.utc(2026, 11, 3);
      final to = DateTime.utc(2026, 11, 4);

      final fixtures = await SportsService(xtream).fixtures(
        capability: capability,
        leagues: capability.leagues,
        from: from,
        to: to,
      );

      final request = requests.last;
      expect(request.action, 'get_sports_fixtures');
      expect(request.params, {
        'leagues': 'hockey/nhl,soccer/eng.1',
        'from': '${from.millisecondsSinceEpoch ~/ 1000}',
        'to': '${to.millisecondsSinceEpoch ~/ 1000}',
      });

      expect(fixtures.map((fixture) => fixture.id), ['1', '2']);
      final fixture = fixtures.first;
      expect(fixture.state, SportsFixtureState.live);
      expect(fixture.statusDetail, '1st - 15:00');
      expect(fixture.league.name, 'NHL');
      expect(fixture.home!.team.key, 'hockey/nhl:tor');
      expect(fixture.home!.team.nickname, 'Maple Leafs');
      expect(fixture.home!.team.logoUrl, contains('/logo-proxy/'));
      expect(fixture.away!.score, '2');
      expect(fixture.broadcasts, ['ESPN+']);
      // North American leagues list the away side first.
      expect(fixture.displayOrder.first.team.displayName, 'Utah Mammoth');
    },
  );

  test("caps a request at the editor's longest range", () async {
    final (xtream, requests) = await _xtream(sports: _sportsPayload());
    final capability = SportsCapability.fromJson({
      ..._sportsPayload(),
      'max_range_days': 3,
    });
    final from = DateTime.utc(2026, 11, 3);

    await SportsService(xtream).fixtures(
      capability: capability,
      leagues: capability.leagues,
      from: from,
      to: from.add(const Duration(days: 10)),
    );

    final to = from.add(const Duration(days: 3));
    expect(requests.last.params['to'], '${to.millisecondsSinceEpoch ~/ 1000}');
  });

  test('tolerates junk replies', () {
    final capability = SportsCapability.fromJson(_sportsPayload());
    expect(SportsService.parseFixtures('nope', capability), isEmpty);
    expect(
      SportsService.parseFixtures({
        'fixtures': ['junk', <String, Object?>{}],
      }, capability),
      isEmpty,
    );
  });
}
