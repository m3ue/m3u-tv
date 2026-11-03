import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/home/home_spotlight.dart';
import 'package:m3u_tv/features/home/home_spotlight_hero.dart';
import 'package:m3u_tv/features/sports/sports_fixture_card.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:material_ui/material_ui.dart';

SportsTeam _team(String id, String name) => SportsTeam(
  leagueId: 'hockey/nhl',
  id: id,
  displayName: name,
  shortName: name,
  nickname: name,
  abbreviation: id.toUpperCase(),
  logoUrl: 'http://img.invalid/$id.png',
);

void main() {
  testWidgets("a game's crests sit in the hero, clear of the rows below", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = HomeSpotlightController(settleDelay: Duration.zero);
    addTearDown(controller.dispose);
    controller.select(
      SportsSpotlightTarget(
        SportsFixture(
          id: '401',
          league: const SportsLeague(
            id: 'hockey/nhl',
            name: 'NHL',
            abbreviation: 'NHL',
          ),
          start: DateTime.now().toUtc(),
          state: SportsFixtureState.live,
          statusDetail: '1st - 15:00',
          home: SportsCompetitor(
            team: _team('tor', 'Toronto Maple Leafs'),
            score: '1',
          ),
          away: SportsCompetitor(
            team: _team('uta', 'Utah Mammoth'),
            score: '0',
          ),
        ),
      ),
    );
    const rowKey = Key('first-row');

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RichHomeLayout(
              controller: controller,
              enricher: HomeSpotlightEnricher(),
              rows: const [SizedBox(key: rowKey, height: 200)],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final crests = find.byType(SportsTeamLogo);
    expect(crests, findsNWidgets(2));
    final rowsTop = tester.getTopLeft(find.byKey(rowKey)).dy;
    for (final crest in crests.evaluate()) {
      expect(
        tester.getRect(find.byWidget(crest.widget)).bottom,
        lessThanOrEqualTo(rowsTop),
      );
    }

    // Let the hero's clock and image timers run out with the tree gone
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  });
}
