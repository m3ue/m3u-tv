import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/sports/sports_fixture_card.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/sports_models.dart';
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

SportsFixture _game(String id, String home, String homeScore, String away) =>
    SportsFixture(
      id: id,
      league: _league,
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
}
