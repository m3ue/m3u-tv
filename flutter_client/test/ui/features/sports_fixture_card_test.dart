import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/sports/sports_fixture_card.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/shared/draggable_text.dart';
import 'package:material_ui/material_ui.dart';

const _league = SportsLeague(
  id: 'soccer/uefa.champions',
  name: 'UEFA Champions League',
  abbreviation: 'UCL',
  soccerStyle: true,
);

SportsTeam _team(String id, String name) => SportsTeam(
  leagueId: _league.id,
  id: id,
  displayName: name,
  shortName: name,
  nickname: name,
  abbreviation: id.toUpperCase(),
);

SportsFixture _game(
  String id,
  String home,
  String homeScore,
  String away, {
  String? leagueLogoUrl,
}) => SportsFixture(
  id: id,
  league: _league,
  leagueLogoUrl: leagueLogoUrl,
  start: DateTime.utc(2026, 11, 3, 20),
  state: SportsFixtureState.live,
  statusDetail: "45'",
  home: SportsCompetitor(team: _team('$id-h', home), score: homeScore),
  away: SportsCompetitor(team: _team('$id-a', away), score: '0'),
);

Widget _card(SportsFixture fixture, int channelCount) => SportsFixtureCard(
  fixture: fixture,
  channelCount: channelCount,
  isResolving: false,
  showLeague: true,
  inMultiview: false,
  onTap: () {},
  onLongTap: () {},
);

void main() {
  testWidgets('lines scores up across cards whatever their channel chip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              _card(_game('1', 'Atletico Madrid', '3', 'Bayern Munich'), 0),
              _card(_game('2', 'Barcelona', '1', 'Aston Villa'), 1),
            ],
          ),
        ),
      ),
    );

    // Scores sit in the same column whatever the chip beside them
    final first = tester.getTopRight(find.text('3')).dx;
    final second = tester.getTopRight(find.text('1')).dx;
    expect(first, second);
    expect(find.text('No channel'), findsOneWidget);
  });

  testWidgets('stacks status and channels above the teams when narrow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: _card(_game('1', 'Atletico Madrid', '3', 'Bayern Munich'), 1),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('1 channel')).dy,
      lessThan(tester.getTopLeft(find.text('Atletico Madrid')).dy),
    );
  });

  group('team names', () {
    const longName = 'Southern Mississippi Golden Eagles of Hattiesburg';

    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: _card(_game('1', longName, '3', 'Howard Bison'), 1),
          ),
        ),
      );
    }

    testWidgets('a phone drags a long name sideways, without scrolling a fit', (
      tester,
    ) async {
      await pumpAt(tester, const Size(380, 800));

      final name = find.ancestor(
        of: find.text(longName),
        matching: find.byType(DraggableText),
      );
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: name, matching: find.byType(Scrollable)),
      );
      await tester.drag(name, const Offset(-60, 0));
      await tester.pump();
      expect(scrollable.position.pixels, greaterThan(0));

      final fits = tester.state<ScrollableState>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Howard Bison'),
            matching: find.byType(DraggableText),
          ),
          matching: find.byType(Scrollable),
        ),
      );
      expect(fits.position.maxScrollExtent, 0);
    });

    testWidgets('tapping a draggable name still opens the game', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SportsFixtureCard(
              fixture: _game('1', longName, '3', 'Howard Bison'),
              channelCount: 1,
              isResolving: false,
              showLeague: false,
              inMultiview: false,
              onTap: () => tapped++,
              onLongTap: () {},
            ),
          ),
        ),
      );

      // Its start: the centre of a name this long is off screen
      await tester.tapAt(
        tester.getTopLeft(find.text(longName)) + const Offset(10, 10),
      );
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });

    testWidgets('a wide card keeps the ellipsis', (tester) async {
      await pumpAt(tester, const Size(1600, 900));

      expect(find.byType(DraggableText), findsNothing);
      expect(
        tester.widget<Text>(find.text(longName)).overflow,
        TextOverflow.ellipsis,
      );
    });

    testWidgets('a Home tile keeps the ellipsis, even on a phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: SportsFixtureTile.baseWidth,
                height: SportsFixtureTile.baseHeight,
                child: SportsFixtureTile(
                  fixture: _game('1', longName, '3', 'Howard Bison'),
                  channelCount: 1,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DraggableText), findsNothing);
    });
  });

  group('league mark', () {
    Future<void> pumpCards(WidgetTester tester, String? leagueLogoUrl) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fixture = _game(
        '1',
        'Barcelona',
        '1',
        'Aston Villa',
        leagueLogoUrl: leagueLogoUrl,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                _card(fixture, 1),
                SizedBox(
                  width: SportsFixtureTile.baseWidth,
                  height: SportsFixtureTile.baseHeight,
                  child: SportsFixtureTile(
                    fixture: fixture,
                    channelCount: 1,
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('shows the logo in place of the abbreviation', (tester) async {
      await pumpCards(tester, 'https://example.test/ucl.png');

      expect(tester.takeException(), isNull);
      expect(find.byType(SportsLeagueMark), findsNWidgets(2));
      expect(find.text('UCL'), findsNothing);
    });

    testWidgets('names the abbreviation when there is no logo', (tester) async {
      await pumpCards(tester, null);

      expect(find.text('UCL'), findsNWidgets(2));
    });

    testWidgets('falls back to the abbreviation when the logo fails', (
      tester,
    ) async {
      await pumpCards(tester, 'https://example.test/ucl.png');

      final mark = find.byType(SportsLeagueMark).first;
      final image = tester.widget<Image>(
        find.descendant(of: mark, matching: find.byType(Image)),
      );
      final fallback = image.errorBuilder!(
        tester.element(mark),
        Exception('load failed'),
        null,
      );
      expect((fallback as Text).data, 'UCL');
    });
  });
}
