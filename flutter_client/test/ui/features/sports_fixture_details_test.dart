import 'package:dpad/dpad.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/sports/sports_fixture_actions.dart';
import 'package:m3u_tv/features/sports/sports_fixture_details_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/sports_channel_lookup.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/sports_service.dart';
import 'package:m3u_tv/services/sports_settings.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/draggable_text.dart';
import 'package:material_ui/material_ui.dart';

const _league = SportsLeague(
  id: 'hockey/nhl',
  name: 'NHL',
  abbreviation: 'NHL',
);
const _capability = SportsCapability(leagues: [_league]);
const _channel = Channel(
  id: 5,
  name: 'NHL 05',
  streamUrl: 'http://example.com/5',
);

const _toronto = SportsTeam(
  leagueId: 'hockey/nhl',
  id: 'tor',
  displayName: 'Toronto Maple Leafs',
  shortName: 'Maple Leafs',
  nickname: 'Maple Leafs',
  abbreviation: 'TOR',
);
const _utah = SportsTeam(
  leagueId: 'hockey/nhl',
  id: 'uta',
  displayName: 'Utah Mammoth',
  shortName: 'Mammoth',
  nickname: 'Mammoth',
  abbreviation: 'UTA',
);

SportsFixture _game(SportsFixtureState state) => SportsFixture(
  id: '401',
  league: _league,
  start: DateTime.utc(2026, 11, 3, 17),
  state: state,
  statusDetail: '3rd - 10:00',
  home: const SportsCompetitor(team: _toronto, score: '2'),
  away: const SportsCompetitor(team: _utah, score: '3'),
);

Map<String, Object?> _team(String id, String name) => {
  'id': id,
  'display_name': name,
  'abbreviation': id.toUpperCase(),
  'color': id == 'tor' ? '003e7e' : '69b3e7',
};

Map<String, Object?> _details({String state = 'finished', String home = '2'}) =>
    {
      'fixture': {
        'id': '401',
        'league_id': 'hockey/nhl',
        'start': '2026-11-03T17:00:00Z',
        'state': state,
        'status_detail': 'Final',
        'home': {'score': home, 'team': _team('tor', 'Toronto Maple Leafs')},
        'away': {'score': '3', 'team': _team('uta', 'Utah Mammoth')},
      },
      'line_score': {
        'periods': ['1', '2', '3'],
        'home': ['0', '1', '1'],
        'away': ['1', '1', '1'],
      },
      'events': [
        {
          'kind': 'score',
          'time': '1st 19:47',
          'side': 'away',
          'text': 'Dylan Guenther Goal (6)',
          'home_score': '0',
          'away_score': '1',
        },
        {
          'kind': 'red_card',
          'time': "90'",
          'side': 'home',
          'text': 'Sent off',
        },
      ],
      'stats': [
        {'label': 'Shots', 'home': '29', 'away': '36'},
        {'label': '3rd down efficiency', 'home': '1-11', 'away': '7-15'},
      ],
      'leaders': [
        {
          'label': 'Goals',
          'home': {'name': 'Jack Roslovic', 'value': '2', 'photo': null},
          'away': null,
        },
      ],
      'info': {
        'venue': 'Scotiabank Arena',
        'location': 'Toronto, Canada',
        'attendance': 18889,
        'officials': ['Garrett Rank'],
        'series': 'UTA wins series 2-0',
        'home_record': '8-7-2',
        'away_record': '10-6-0',
      },
    };

void main() {
  late List<Object?> responses;
  late SportsSettings settings;
  late int requests;

  Future<XtreamService> editor() async {
    final service = XtreamService(
      transport: (request) async {
        if (request.action == null) {
          return {
            'user_info': {'auth': 1, 'status': 'Active'},
            'server_info': {'timezone': 'UTC'},
            'm3u_editor': {
              'version': '0.14.0',
              'features': ['sports'],
            },
          };
        }
        expect(request.action, 'get_sports_fixture_details');
        expect(request.params['league'], 'hockey/nhl');
        expect(request.params['fixture'], '401');
        final answer =
            responses[requests < responses.length
                ? requests
                : responses.length - 1];
        requests++;
        if (answer is Exception) throw answer;
        return answer;
      },
    );
    await service.authenticate(
      const UserCredentials(
        server: 'https://editor.example',
        username: 'user',
        password: 'pass',
      ),
    );
    return service;
  }

  setUp(() {
    responses = [];
    requests = 0;
    settings = SportsSettings();
  });

  /// A page that opens the game the way pressing it does.
  Future<void> pumpHost(
    WidgetTester tester, {
    required SportsFixture fixture,
    List<SportsChannelMatch> matches = const [],
    ValueChanged<Channel>? onChannelSelect,
    Size size = const Size(1000, 2400),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final xtream = await editor();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sportsCapabilityProvider.overrideWith((_) => _capability),
          sportsServiceProvider.overrideWith((_) => SportsService(xtream)),
          sportsSettingsProvider.overrideWith((_) => settings),
        ],
        child: Dpad(
          child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => openSportsFixture(
                    context,
                    fixture: fixture,
                    matches: matches,
                    onChannelSelect: onChannelSelect ?? (_) {},
                  ),
                  child: const Text('Open game'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open game'));
    await tester.pumpAndSettle();
  }

  testWidgets('a finished game opens its details, with every section', (
    tester,
  ) async {
    responses = [
      {'details': _details()},
    ];
    await pumpHost(tester, fixture: _game(SportsFixtureState.finished));

    expect(find.byType(SportsFixtureDetailsScreen), findsOneWidget);
    expect(find.text('Toronto Maple Leafs'), findsOneWidget);
    expect(find.text('8-7-2'), findsOneWidget);
    expect(find.text('3 - 2'), findsOneWidget);
    // Too long for a bar to mean anything, but still listed
    expect(find.text('3rd down efficiency'), findsOneWidget);
    expect(find.text('Score by period'), findsOneWidget);
    expect(find.text('Dylan Guenther Goal (6)'), findsOneWidget);
    // NHL reads away first
    expect(find.text('1-0'), findsOneWidget);
    expect(find.text('Team stats'), findsOneWidget);
    expect(find.text('Top performers'), findsOneWidget);
    expect(find.text('Jack Roslovic'), findsOneWidget);
    expect(find.text('Scotiabank Arena, Toronto, Canada'), findsOneWidget);
    expect(find.text('18,889'), findsOneWidget);
    expect(find.text('On Your Channels'), findsNothing);
    expect(requests, 1);
  });

  testWidgets('a live game with a channel plays on press, no details', (
    tester,
  ) async {
    Channel? played;
    await pumpHost(
      tester,
      fixture: _game(SportsFixtureState.live),
      matches: const [SportsChannelMatch(channel: _channel)],
      onChannelSelect: (channel) => played = channel,
    );

    expect(played, _channel);
    expect(find.byType(SportsFixtureDetailsScreen), findsNothing);
    expect(requests, 0);
  });

  testWidgets('a live game no channel carries opens details, and refreshes', (
    tester,
  ) async {
    responses = [
      {'details': _details(state: 'live')},
      {'details': _details(state: 'live', home: '4')},
      {'details': _details()},
    ];
    await pumpHost(tester, fixture: _game(SportsFixtureState.live));
    expect(requests, 1);
    expect(find.text('On Your Channels'), findsNothing);
    expect(find.text('3 - 2'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(requests, 2);
    expect(find.text('3 - 4'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(requests, 3);

    // It's over: nothing more to ask for
    await tester.pump(const Duration(minutes: 5));
    expect(requests, 3);
  });

  testWidgets('a listed channel closes the details and plays', (tester) async {
    responses = [
      {'details': _details(state: 'live')},
    ];
    Channel? played;
    tester.view
      ..physicalSize = const Size(1000, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final xtream = await editor();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sportsCapabilityProvider.overrideWith((_) => _capability),
          sportsServiceProvider.overrideWith((_) => SportsService(xtream)),
          sportsSettingsProvider.overrideWith((_) => settings),
        ],
        child: Dpad(
          child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => openSportsFixtureDetails(
                    context,
                    fixture: _game(SportsFixtureState.live),
                    matches: const [SportsChannelMatch(channel: _channel)],
                    onChannelSelect: (channel) => played = channel,
                  ),
                  child: const Text('Open game'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open game'));
    await tester.pumpAndSettle();

    expect(find.text('On Your Channels'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DraggableText),
        matching: find.text('NHL 05'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.play_circle_fill));
    await tester.pumpAndSettle();

    expect(played, _channel);
    expect(find.byType(SportsFixtureDetailsScreen), findsNothing);
  });

  testWidgets('says so when there are no details, keeping the scoreboard', (
    tester,
  ) async {
    responses = [
      {'details': null},
    ];
    await pumpHost(tester, fixture: _game(SportsFixtureState.finished));

    expect(find.text('Toronto Maple Leafs'), findsOneWidget);
    expect(
      find.text('No more details are available for this game yet.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(minutes: 2));
    expect(requests, 1);
  });

  testWidgets('retries a failed load', (tester) async {
    responses = [
      Exception('offline'),
      {'details': _details()},
    ];
    await pumpHost(tester, fixture: _game(SportsFixtureState.finished));
    expect(
      find.text("Couldn't load game details. Retrying shortly."),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();

    expect(find.text('Score by period'), findsOneWidget);
    expect(find.textContaining("Couldn't load"), findsNothing);
  });

  testWidgets('labels numbers before a game as the season so far', (
    tester,
  ) async {
    responses = [
      {'details': _details(state: 'scheduled')},
    ];
    await pumpHost(tester, fixture: _game(SportsFixtureState.scheduled));

    expect(find.text('Season stats'), findsOneWidget);
    expect(find.text('Season leaders'), findsOneWidget);
    expect(find.text('Team stats'), findsNothing);
  });

  testWidgets('fits a phone without overflowing', (tester) async {
    responses = [
      {'details': _details()},
    ];
    await pumpHost(
      tester,
      fixture: _game(SportsFixtureState.finished),
      size: const Size(360, 780),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Toronto Maple Leafs'), findsOneWidget);
  });

  testWidgets('follows a team from its column', (tester) async {
    responses = [
      {'details': _details()},
    ];
    await pumpHost(tester, fixture: _game(SportsFixtureState.finished));
    expect(find.text('Follow'), findsNWidgets(2));

    await tester.tap(find.text('Follow').first);
    await tester.pumpAndSettle();

    expect(find.text('Following'), findsOneWidget);
    expect(settings.isFollowing(_utah.key), isTrue);
  });

  testWidgets('Up from reading goes back to the buttons once at the top', (
    tester,
  ) async {
    responses = [
      {'details': _details()},
    ];
    await pumpHost(
      tester,
      fixture: _game(SportsFixtureState.finished),
      size: const Size(600, 400),
    );
    expect(find.text('Follow'), findsNWidgets(2));
    final reading = FocusManager.instance.primaryFocus;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus, isNot(reading));
  });

  testWidgets("washes the page in both teams' colours", (tester) async {
    responses = [
      {'details': _details()},
    ];
    await pumpHost(tester, fixture: _game(SportsFixtureState.finished));

    final gradients = tester
        .widgetList<DecoratedBox>(
          find.ancestor(
            of: find.byType(Scaffold).last,
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => (box.decoration as BoxDecoration).gradient)
        .whereType<LinearGradient>();
    expect(gradients.single.colors, [
      const Color(0xFF69B3E7).withValues(alpha: 0.32),
      const Color(0xFF003E7E).withValues(alpha: 0.32),
    ]);
  });

  testWidgets('the sections take focus without drawing a border', (
    tester,
  ) async {
    responses = [
      {'details': _details()},
    ];
    await pumpHost(tester, fixture: _game(SportsFixtureState.finished));

    final sections = find.ancestor(
      of: find.text('Team stats'),
      matching: find.byType(DpadFocusable),
    );
    expect(tester.widget<DpadFocusable>(sections).effects, isEmpty);
    // The scrollbar is what shows focus there instead.
    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar).first).thumbVisibility,
      isTrue,
    );
  });

  testWidgets('D-pad Down scrolls the page', (tester) async {
    responses = [
      {'details': _details()},
    ];
    await pumpHost(
      tester,
      fixture: _game(SportsFixtureState.finished),
      size: const Size(600, 400),
    );
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SportsFixtureDetailsScreen),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          )
          .first,
    );
    expect(scrollable.position.pixels, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
  });
}
