import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/sports/sports_fixture_card.dart';
import 'package:m3u_tv/features/sports/sports_screen.dart';
import 'package:m3u_tv/features/sports/sports_teams_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/sports_service.dart';
import 'package:m3u_tv/services/sports_settings.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/day_toolbar.dart';
import 'package:m3u_tv/shared/media_category_nav.dart';
import 'package:material_ui/material_ui.dart';

typedef XtreamRequestRecord = ({String? action, Map<String, String> params});

const _eventChannel = Channel(
  id: 5,
  name: 'NHL 05: Mammoth @ Maple Leafs',
  streamUrl: 'http://example.com/5',
);
const _otherChannel = Channel(
  id: 6,
  name: 'News 24',
  streamUrl: 'http://example.com/6',
);

const _capability = SportsCapability(
  teamsAction: 'get_sports_teams',
  leagues: [
    SportsLeague(
      id: 'hockey/nhl',
      name: 'NHL',
      abbreviation: 'NHL',
      isDefault: true,
    ),
  ],
);

Map<String, Object?> _team(String id, String name, String nickname) => {
  'id': id,
  'display_name': name,
  'short_name': nickname,
  'nickname': nickname,
  'abbreviation': id.toUpperCase(),
};

/// An editor serving one live NHL game (no crest URLs, so nothing reaches
/// the image cache).
Future<XtreamService> _editor({
  List<XtreamRequestRecord>? requests,
  Future<Object?> Function()? channels,
  String gameState = 'live',
  bool noGames = false,
}) async {
  final service = XtreamService(
    transport: (request) async {
      requests?.add((action: request.action, params: request.params));
      if (request.action == 'get_sports_channels') {
        if (channels != null) return channels();
        return {
          'channels': {
            'hockey/nhl:401': [
              {'stream_id': 5, 'program_title': null},
              // Not in this device's catalog
              {'stream_id': 99, 'program_title': 'NHL Hockey'},
            ],
          },
        };
      }
      if (request.action == 'get_sports_teams') {
        return {
          'teams': [
            _team('tor', 'Toronto Maple Leafs', 'Maple Leafs'),
            _team('uta', 'Utah Mammoth', 'Mammoth'),
          ],
        };
      }
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
      if (noGames) return {'fixtures': const <Object>[]};
      return {
        'fixtures': [
          {
            'id': '401',
            'league_id': 'hockey/nhl',
            'start': DateTime.now().toUtc().toIso8601String(),
            'state': gameState,
            'status_detail': '1st - 15:00',
            'home': {
              'score': '1',
              'team': _team('tor', 'Toronto Maple Leafs', 'Maple Leafs'),
            },
            'away': {
              'score': '0',
              'team': _team('uta', 'Utah Mammoth', 'Mammoth'),
            },
          },
        ],
      };
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

Future<CatalogRepository> _buildRepo(WidgetTester tester) async {
  final repo = await tester.runAsync(() async {
    final db = CatalogDatabase.memory();
    addTearDown(db.close);
    final repo = CatalogRepository(db);
    await repo.replaceItems(
      sourceKey: CatalogRepository.defaultSource,
      kind: kCatalogKindLive,
      items: const [_eventChannel, _otherChannel],
    );
    return repo;
  });
  return repo!;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required CatalogRepository repo,
  required SportsSettings settings,
  required SportsCapability? capability,
  XtreamService? editor,
  List<Channel>? opened,
  bool dpad = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isBootstrappingProvider.overrideWith((_) => false),
        isConfiguredProvider.overrideWith((_) => true),
        catalogRepositoryProvider.overrideWith((_) => repo),
        shownPlaylistKeyProvider.overrideWith((_) => null),
        epgServiceProvider.overrideWith((_) => EpgService()),
        sportsSettingsProvider.overrideWith((_) => settings),
        sportsCapabilityProvider.overrideWith((_) => capability),
        if (editor != null)
          sportsServiceProvider.overrideWith((_) => SportsService(editor)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: dpad ? (context, child) => Dpad(child: child!) : null,
        home: SportsScreen(
          onChannelSelect: (channel) => opened?.add(channel),
          useSidebarLayout: true,
        ),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  testWidgets(
    'lists a live game with its channel, plays it, and follows a team',
    (tester) async {
      final repo = await _buildRepo(tester);
      final editor = (await tester.runAsync(_editor))!;
      final settings = SportsSettings();
      final opened = <Channel>[];

      await _pumpScreen(
        tester,
        repo: repo,
        settings: settings,
        capability: _capability,
        editor: editor,
        opened: opened,
      );

      expect(find.text('Live Now'), findsOneWidget);
      expect(find.text('Toronto Maple Leafs'), findsOneWidget);
      expect(find.text('1 channel'), findsOneWidget);

      // One channel carries it, so a press plays it straight away.
      await tester.tap(find.text('Toronto Maple Leafs'));
      await _settle(tester);
      expect(opened.map((channel) => channel.id), [_eventChannel.id]);

      await tester.longPress(find.text('Utah Mammoth'));
      await _settle(tester);
      await tester.tap(find.text('Follow Utah Mammoth'));
      await _settle(tester);
      expect(settings.isFollowing('hockey/nhl:uta'), isTrue);

      // "My Teams" now lists the game.
      await tester.tap(find.text('My Teams'));
      await _settle(tester);
      expect(find.text('Toronto Maple Leafs'), findsOneWidget);

      // Unmount so the live-score refresh timer is cancelled.
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('follows a team from the team browser into My Teams', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);
    final editor = (await tester.runAsync(_editor))!;
    final settings = SportsSettings();

    await _pumpScreen(
      tester,
      repo: repo,
      settings: settings,
      capability: _capability,
      editor: editor,
    );

    await tester.tap(find.text('Teams'));
    await _settle(tester);
    expect(find.text('Pick your teams'), findsOneWidget);

    await tester.tap(find.text('Utah Mammoth'));
    await _settle(tester);
    expect(settings.isFollowing('hockey/nhl:uta'), isTrue);

    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);
    await tester.tap(find.text('My Teams'));
    await _settle(tester);
    expect(find.text('Toronto Maple Leafs'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('picks leagues by sport, then league', (tester) async {
    final repo = await _buildRepo(tester);
    final editor = (await tester.runAsync(_editor))!;
    final settings = SportsSettings();
    const capability = SportsCapability(
      leagues: [
        SportsLeague(
          id: 'hockey/nhl',
          name: 'NHL',
          abbreviation: 'NHL',
          isDefault: true,
          sportDisplayName: 'Hockey',
        ),
        SportsLeague(
          id: 'soccer/eng.1',
          name: 'Premier League',
          abbreviation: 'EPL',
          sportDisplayName: 'Soccer',
        ),
        SportsLeague(
          id: 'soccer/usa.ncaa.m.1',
          name: "NCAA Men's Soccer",
          abbreviation: 'CMSOC',
          sportDisplayName: 'Soccer',
        ),
      ],
    );

    await _pumpScreen(
      tester,
      repo: repo,
      settings: settings,
      capability: capability,
      editor: editor,
    );

    await tester.tap(find.text('Leagues'));
    await _settle(tester);
    expect(find.text('Hockey'), findsOneWidget);
    expect(find.text('1 of 1 shown'), findsOneWidget);
    expect(find.text('0 of 2 shown'), findsOneWidget);

    await tester.tap(find.text('Soccer'));
    await _settle(tester);
    await tester.tap(find.text("NCAA Men's Soccer"));
    await _settle(tester);
    expect(settings.enabledLeagues(capability.leagues).map((l) => l.id), [
      'hockey/nhl',
      'soccer/usa.ncaa.m.1',
    ]);

    await tester.tap(find.text('Done').last);
    await _settle(tester);
    expect(find.text('1 of 2 shown'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  Iterable<XtreamRequestRecord> fixtureRequests(
    List<XtreamRequestRecord> requests,
  ) => requests.where((request) => request.action == 'get_sports_fixtures');

  Iterable<XtreamRequestRecord> channelRequests(
    List<XtreamRequestRecord> requests,
  ) => requests.where((request) => request.action == 'get_sports_channels');

  String dayStart(int offset) {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day + offset);
    return '${day.millisecondsSinceEpoch ~/ 1000}';
  }

  Future<void> afterDayChange(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await _settle(tester);
  }

  testWidgets('requests one local day at a time, once for fast presses', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);
    final requests = <XtreamRequestRecord>[];
    final editor = (await tester.runAsync(() => _editor(requests: requests)))!;

    await _pumpScreen(
      tester,
      repo: repo,
      settings: SportsSettings(),
      capability: _capability,
      editor: editor,
    );
    expect(fixtureRequests(requests).last.params['from'], dayStart(0));
    expect(fixtureRequests(requests).last.params['to'], dayStart(1));
    // The day shown, and the button back to it
    expect(find.text('Today'), findsNWidgets(2));
    expect(find.text('Now'), findsNothing);
    final initial = fixtureRequests(requests).length;

    await tester.tap(find.byKey(const ValueKey('sports-next-day')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sports-next-day')));
    await afterDayChange(tester);
    expect(fixtureRequests(requests).length, initial + 1);
    expect(fixtureRequests(requests).last.params['from'], dayStart(2));

    await tester.tap(find.byKey(const ValueKey('sports-now')));
    await afterDayChange(tester);
    expect(fixtureRequests(requests).last.params['from'], dayStart(0));
    expect(channelRequests(requests).last.params['from'], dayStart(0));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stops at the ends of the date range', (tester) async {
    final repo = await _buildRepo(tester);
    final editor = (await tester.runAsync(_editor))!;

    await _pumpScreen(
      tester,
      repo: repo,
      settings: SportsSettings(),
      capability: _capability,
      editor: editor,
    );

    DayToolbar toolbar() => tester.widget<DayToolbar>(find.byType(DayToolbar));
    for (var i = 0; i < 7; i++) {
      expect(toolbar().canGoPrevious, isTrue);
      await tester.tap(find.byKey(const ValueKey('sports-previous-day')));
      await tester.pump();
    }
    expect(toolbar().canGoPrevious, isFalse);

    await tester.tap(find.byKey(const ValueKey('sports-now')));
    await tester.pump();
    for (var i = 0; i < 14; i++) {
      expect(toolbar().canGoNext, isTrue);
      await tester.tap(find.byKey(const ValueKey('sports-next-day')));
      await tester.pump();
    }
    expect(toolbar().canGoNext, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows games while their channels load, then the count', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);
    final channels = Completer<Object?>();
    final editor = (await tester.runAsync(
      () => _editor(channels: () => channels.future),
    ))!;

    await _pumpScreen(
      tester,
      repo: repo,
      settings: SportsSettings(),
      capability: _capability,
      editor: editor,
    );
    expect(find.text('Toronto Maple Leafs'), findsOneWidget);
    expect(find.text('1 channel'), findsNothing);

    channels.complete({
      'channels': {
        'hockey/nhl:401': [
          {'stream_id': 5},
        ],
      },
    });
    await _settle(tester);
    expect(find.text('1 channel'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps showing games when finding channels fails', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);
    final editor = (await tester.runAsync(
      () => _editor(channels: () async => throw StateError('offline')),
    ))!;

    await _pumpScreen(
      tester,
      repo: repo,
      settings: SportsSettings(),
      capability: _capability,
      editor: editor,
    );

    expect(find.text('Toronto Maple Leafs'), findsOneWidget);
    expect(find.text('Live Now'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a score refresh does not ask for channels again', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);
    final requests = <XtreamRequestRecord>[];
    final editor = (await tester.runAsync(() => _editor(requests: requests)))!;

    await _pumpScreen(
      tester,
      repo: repo,
      settings: SportsSettings(),
      capability: _capability,
      editor: editor,
    );
    final fixtures = fixtureRequests(requests).length;
    expect(channelRequests(requests), hasLength(1));

    await tester.pump(const Duration(minutes: 1));
    await _settle(tester);

    expect(fixtureRequests(requests).length, fixtures + 1);
    expect(channelRequests(requests), hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('skips the channels request when every game is over', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);
    final requests = <XtreamRequestRecord>[];
    final editor = (await tester.runAsync(
      () => _editor(requests: requests, gameState: 'finished'),
    ))!;

    await _pumpScreen(
      tester,
      repo: repo,
      settings: SportsSettings(),
      capability: _capability,
      editor: editor,
    );

    expect(find.text('Toronto Maple Leafs'), findsOneWidget);
    expect(channelRequests(requests), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('opens on All when no followed team plays that day', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);
    final editor = (await tester.runAsync(_editor))!;
    final settings = SportsSettings();
    await tester.runAsync(
      () => settings.toggleFollow(
        const SportsTeam(
          leagueId: 'hockey/nhl',
          id: 'bos',
          displayName: 'Boston Bruins',
          shortName: 'Bruins',
          nickname: 'Bruins',
          abbreviation: 'BOS',
        ),
      ),
    );

    await _pumpScreen(
      tester,
      repo: repo,
      settings: settings,
      capability: _capability,
      editor: editor,
    );
    expect(find.text('Toronto Maple Leafs'), findsOneWidget);

    // A tab the viewer picks stands, even with nothing to show.
    await tester.tap(find.text('My Teams'));
    await _settle(tester);
    expect(find.text('Toronto Maple Leafs'), findsNothing);
    expect(find.text('None of your teams play on this day'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Up from the top game moves to the date bar', (tester) async {
    final repo = await _buildRepo(tester);
    final editor = (await tester.runAsync(_editor))!;

    await _pumpScreen(
      tester,
      repo: repo,
      settings: SportsSettings(),
      capability: _capability,
      editor: editor,
      dpad: true,
    );

    final card = find
        .ancestor(
          of: find.text('Toronto Maple Leafs'),
          matching: find.byType(DpadFocusable),
        )
        .first;
    tester
        .widget<Focus>(
          find.descendant(of: card, matching: find.byType(Focus)).first,
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await _settle(tester);

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'sports-now',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('sits right of the filter strip, above the games', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);
    final editor = (await tester.runAsync(_editor))!;

    await _pumpScreen(
      tester,
      repo: repo,
      settings: SportsSettings(),
      capability: _capability,
      editor: editor,
    );

    final toolbar = tester.getRect(find.byType(DayToolbar));
    expect(
      toolbar.left,
      greaterThanOrEqualTo(tester.getRect(find.byType(MediaCategoryNav)).right),
    );
    expect(
      toolbar.bottom,
      lessThanOrEqualTo(tester.getTopLeft(find.text('Live Now')).dy),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('moves between the strip, the date bar and the games', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);
    final editor = (await tester.runAsync(_editor))!;

    await _pumpScreen(
      tester,
      repo: repo,
      settings: SportsSettings(),
      capability: _capability,
      editor: editor,
      dpad: true,
    );

    bool focusIsIn(Finder finder) {
      final focused = FocusManager.instance.primaryFocus?.context;
      return focused != null &&
          tester.widgetList(finder).any((widget) {
            var found = false;
            focused.visitAncestorElements((element) {
              found = identical(element.widget, widget);
              return !found;
            });
            return found;
          });
    }

    final now = tester.widget<Focus>(
      find
          .descendant(
            of: find.byKey(const ValueKey('sports-now')),
            matching: find.byType(Focus),
          )
          .first,
    );
    now.focusNode!.requestFocus();
    await tester.pump();

    // Down from the date bar reaches the games
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester);
    expect(focusIsIn(find.byType(SportsFixtureCard)), isTrue);

    // Left from the games reaches the strip, and Right returns
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(focusIsIn(find.byType(MediaCategoryNav)), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(focusIsIn(find.byType(MediaCategoryNav)), isFalse);

    // Left from the date bar reaches the strip
    now.focusNode!.requestFocus();
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _settle(tester);
    }
    expect(focusIsIn(find.byType(MediaCategoryNav)), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Right from the strip reaches the date bar on an empty day', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);
    final editor = (await tester.runAsync(() => _editor(noGames: true)))!;

    await _pumpScreen(
      tester,
      repo: repo,
      settings: SportsSettings(),
      capability: _capability,
      editor: editor,
      dpad: true,
    );
    expect(find.text('No games on this day'), findsOneWidget);

    final allTab = find
        .ancestor(
          of: find.text('All Leagues'),
          matching: find.byType(DpadFocusable),
        )
        .first;
    tester
        .widget<Focus>(
          find.descendant(of: allTab, matching: find.byType(Focus)).first,
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sports-now');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('opens Teams over the sidebar, without resizing the shell', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);
    final editor = (await tester.runAsync(_editor))!;
    var shellResizes = 0;
    var backs = 0;
    final rootKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isBootstrappingProvider.overrideWith((_) => false),
          isConfiguredProvider.overrideWith((_) => true),
          catalogRepositoryProvider.overrideWith((_) => repo),
          shownPlaylistKeyProvider.overrideWith((_) => null),
          sportsSettingsProvider.overrideWith((_) => SportsSettings()),
          sportsCapabilityProvider.overrideWith((_) => _capability),
          sportsServiceProvider.overrideWith((_) => SportsService(editor)),
        ],
        child: MaterialApp(
          navigatorKey: rootKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => Dpad(child: child!),
          // Sports sits in a branch Navigator under the shell, as in the app
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => SportsScreen(
                onChannelSelect: (_) {},
                useSidebarLayout: true,
                onEnterFullScreenDetail: () => shellResizes++,
                onHandleTopLevelBack: () {
                  backs++;
                  rootKey.currentState!.pop();
                  return true;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Teams'));
    await _settle(tester);

    expect(find.byType(SportsTeamsScreen), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(SportsTeamsScreen))),
      same(rootKey.currentState),
    );
    expect(shellResizes, 0);

    // Focus starts inside the page, so the remote works straight away
    final teamsScreen = tester.element(find.byType(SportsTeamsScreen));
    bool focusInTeams() {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null) return false;
      var inside = identical(focused, teamsScreen);
      focused.visitAncestorElements((element) {
        inside = inside || identical(element, teamsScreen);
        return !inside;
      });
      return inside;
    }

    expect(focusInTeams(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester);
    expect(focusInTeams(), isTrue);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<DpadFocusable>(),
      isNotNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);

    expect(backs, 1);
    expect(find.byType(SportsTeamsScreen), findsNothing);
    expect(find.text('Toronto Maple Leafs'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('explains when the editor has Sports turned off', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);

    await _pumpScreen(
      tester,
      repo: repo,
      settings: SportsSettings(),
      capability: null,
    );

    expect(
      find.textContaining('Settings > Integrations > Sports'),
      findsOneWidget,
    );
  });
}
