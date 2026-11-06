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
  'sport_names': {'soccer': 'Soccer'},
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
  'league_logo': 'https://editor.example/logo-proxy/nhl-dark',
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
  group('parseDetails', () {
    const capability = SportsCapability(
      leagues: [
        SportsLeague(id: 'hockey/nhl', name: 'NHL', abbreviation: 'NHL'),
      ],
    );

    test('maps every section', () {
      final details = SportsService.parseDetails({
        'details': {
          'fixture': {
            'id': '401',
            'league_id': 'hockey/nhl',
            'start': '2026-11-03T17:00:00Z',
            'state': 'live',
            'status_detail': '3rd - 10:00',
          },
          'line_score': {
            'periods': ['1', 'OT'],
            'home': ['0', '1'],
            'away': ['1', '-'],
          },
          'events': [
            {
              'kind': 'yellow_card',
              'time': "34'",
              'side': 'away',
              'text': 'Booked',
            },
            {'kind': 'score', 'text': 'Goal', 'home_score': 1, 'away_score': 0},
            {'kind': 'score'},
          ],
          'stats': [
            {'label': 'Shots', 'home': '29', 'away': '36'},
            {'label': 'One-sided', 'home': '1'},
          ],
          'leaders': [
            {
              'label': 'Goals',
              'home': {'name': 'Jack', 'value': '2', 'photo': 'http://x/j.png'},
              'away': null,
            },
          ],
          'info': {
            'venue': 'Arena',
            'location': 'Toronto, Canada',
            'attendance': 18889,
            'officials': ['Ref'],
            'series': 'Tied 1-1',
            'home_record': '8-7-2',
            'away_record': '10-6-0',
          },
        },
      }, capability)!;

      expect(details.fixture?.state, SportsFixtureState.live);
      expect(details.lineScore?.periods, ['1', 'OT']);
      expect(details.lineScore?.away, ['1', '-']);
      expect(details.events, hasLength(2));
      expect(details.events.first.kind, SportsEventKind.yellowCard);
      expect(details.events.first.side, SportsSide.away);
      expect(details.events.last.homeScore, '1');
      expect(details.stats.single.label, 'Shots');
      expect(details.leaders.single.home?.photoUrl, 'http://x/j.png');
      expect(details.leaders.single.away, isNull);
      expect(details.venue, 'Arena');
      expect(details.attendance, 18889);
      expect(details.officials, ['Ref']);
      expect(details.series, 'Tied 1-1');
      expect(details.awayRecord, '10-6-0');
    });

    test('reads null and missing sections as nothing', () {
      expect(SportsService.parseDetails({'details': null}, capability), isNull);
      expect(SportsService.parseDetails('nope', capability), isNull);

      final details = SportsService.parseDetails({
        'details': {
          'line_score': {
            'periods': ['1'],
            'home': <String>[],
            'away': ['1'],
          },
        },
      }, capability)!;
      expect(details.fixture, isNull);
      expect(details.lineScore, isNull);
      expect(details.events, isEmpty);
    });
  });

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
    // The sport comes from the id; its name from the editor when sent.
    expect(sports.leagueById('soccer/eng.1')!.sport, 'soccer');
    expect(sports.leagueById('soccer/eng.1')!.sportName, 'Soccer');
    expect(sports.leagueById('hockey/nhl')!.sportName, 'hockey');
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
      expect(
        fixture.leagueLogoUrl,
        'https://editor.example/logo-proxy/nhl-dark',
      );
      // North American leagues list the away side first.
      expect(fixture.displayOrder.first.team.displayName, 'Utah Mammoth');
    },
  );

  test('asks for a day of channels and reads them by game', () async {
    final (xtream, requests) = await _xtream(sports: _sportsPayload());
    final capability = SportsCapability.fromJson(_sportsPayload());
    final from = DateTime.utc(2026, 11, 3);
    final to = DateTime.utc(2026, 11, 4);

    await SportsService(xtream).channels(
      capability: capability,
      leagues: capability.leagues,
      from: from,
      to: to,
    );

    expect(requests.last.action, 'get_sports_channels');
    expect(requests.last.method, 'POST');
    expect(requests.last.body, {
      'leagues': 'hockey/nhl,soccer/eng.1',
      'from': '${from.millisecondsSinceEpoch ~/ 1000}',
      'to': '${to.millisecondsSinceEpoch ~/ 1000}',
    });

    final channels = SportsService.parseChannels({
      'channels': {
        'hockey/nhl:401': [
          {'stream_id': 5, 'program_title': 'NHL Hockey'},
          {'stream_id': 6, 'program_title': null},
          {'stream_id': 'junk'},
          'junk',
        ],
        'hockey/nhl:402': 'junk',
      },
    });
    expect(channels.keys, ['hockey/nhl:401']);
    expect(channels['hockey/nhl:401']!.map((ref) => ref.streamId), [5, 6]);
    expect(channels['hockey/nhl:401']!.first.programTitle, 'NHL Hockey');
    expect(channels['hockey/nhl:401']!.last.programTitle, isNull);
    // PHP sends an empty map as an object, but never mind a list
    expect(SportsService.parseChannels({'channels': <Object>[]}), isEmpty);
    expect(SportsService.parseChannels('junk'), isEmpty);
  });

  group('a long league list', () {
    final leagues = [
      for (var i = 0; i < 70; i++)
        {'id': 'soccer/league.$i', 'name': 'League $i'},
    ];
    final capability = SportsCapability.fromJson({
      ..._sportsPayload(),
      'leagues': leagues,
    });
    final from = DateTime.utc(2026, 11, 3);
    final to = DateTime.utc(2026, 11, 4);

    /// A service whose fixtures requests go to [answer].
    Future<(XtreamService, List<XtreamRequest>)> service(
      Object? Function(XtreamRequest request) answer,
    ) async {
      final requests = <XtreamRequest>[];
      final xtream = XtreamService(
        transport: (request) async {
          if (request.action == null) {
            return {
              'user_info': {'auth': 1, 'status': 'Active'},
              'server_info': {'timezone': 'UTC'},
              'm3u_editor': {
                'version': '0.14.1',
                'features': ['sports'],
                'sports': _sportsPayload(),
              },
            };
          }
          requests.add(request);
          return answer(request);
        },
      );
      await xtream.authenticate(_credentials);
      return (xtream, requests);
    }

    Map<String, Object?> gameOfFirstLeague(XtreamRequest request) {
      final league = request.params['leagues']!.split(',').first;
      final number = league.split('.').last;
      return {
        'fixtures': [
          _fixture(
            number,
            '2026-11-03T${number.padLeft(2, '0')}:00:00Z',
            league: league,
          ),
        ],
      };
    }

    test('is fetched in short batches and merged, soonest first', () async {
      final (xtream, requests) = await service(gameOfFirstLeague);

      final fixtures = await SportsService(xtream).fixtures(
        capability: capability,
        leagues: capability.leagues,
        from: from,
        to: to,
      );

      expect(requests, hasLength(3));
      final asked = [
        for (final request in requests)
          ...request.params['leagues']!.split(','),
      ];
      expect(asked.toSet(), hasLength(70));
      expect(
        requests.map((request) => request.params['leagues']!.split(',').length),
        everyElement(lessThanOrEqualTo(30)),
      );
      expect(fixtures.map((fixture) => fixture.id), ['0', '30', '60']..sort());
      expect(fixtures.first.start.isBefore(fixtures.last.start), isTrue);
    });

    test('keeps the games of the batches that worked', () async {
      final (xtream, _) = await service((request) {
        if (request.params['leagues']!.startsWith('soccer/league.30,')) {
          throw Exception('timed out');
        }
        return gameOfFirstLeague(request);
      });

      final fixtures = await SportsService(xtream).fixtures(
        capability: capability,
        leagues: capability.leagues,
        from: from,
        to: to,
      );

      expect(fixtures.map((fixture) => fixture.id), ['0', '60']);
    });

    test('fails when every batch does', () async {
      final (xtream, _) = await service((_) => throw Exception('down'));

      expect(
        SportsService(xtream).fixtures(
          capability: capability,
          leagues: capability.leagues,
          from: from,
          to: to,
        ),
        throwsException,
      );
    });
  });

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

  test('reads the optional team and follow actions', () {
    final full = SportsCapability.fromJson({
      ..._sportsPayload(),
      'actions': {
        'fixtures': 'get_sports_fixtures',
        'teams': 'get_sports_teams',
        'follows': 'get_sports_follows',
        'toggle_follow': 'toggle_sports_follow',
        'sync_follows': 'sync_sports_follows',
      },
    });
    expect(full.listsTeams, isTrue);
    expect(full.syncsFollows, isTrue);

    // An editor from before the team browser: fixtures only.
    final older = SportsCapability.fromJson(_sportsPayload());
    expect(older.listsTeams, isFalse);
    expect(older.syncsFollows, isFalse);
  });

  test("maps a league's teams", () {
    final teams = SportsService.parseTeams({
      'teams': [
        _side('ana', 'Anaheim Ducks', 'Ducks')['team'],
        'junk',
        _side('tor', 'Toronto Maple Leafs', 'Maple Leafs')['team'],
      ],
    }, 'hockey/nhl');
    expect(teams.map((team) => team.key), ['hockey/nhl:ana', 'hockey/nhl:tor']);
    expect(teams.last.logoUrl, contains('/logo-proxy/'));
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
