import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/navigation/nav_layout.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/services/client_config.dart';
import 'package:m3u_tv/services/home_screen_config.dart';
import 'package:m3u_tv/services/view_settings_service.dart';

Map<String, Object?> _homeScreenJson({
  String mode = 'default',
  List<Map<String, Object?>>? sections,
}) => {
  'mode': mode,
  'sections':
      sections ??
      [
        {
          'section': 'series',
          'nav': false,
          'home': true,
          'rows': [
            {
              'id': 'xmas',
              'kind': 'category',
              'title': 'Christmas',
              'params': {'category_id': '812'},
              'window': {'from': '12-01', 'to': '12-31'},
            },
            {'id': 'default', 'kind': 'default'},
          ],
        },
        {
          'section': 'sports',
          'nav': true,
          'home': true,
          'rows': [
            {'id': 'default', 'kind': 'default'},
            {
              'id': 'game-day',
              'kind': 'sports_fixtures',
              'title': 'Game Day',
              'params': {
                'leagues': ['football/nfl'],
                'range': 'next_3_days',
                'limit': 8,
              },
            },
          ],
        },
        {'section': 'live_tv', 'nav': true, 'home': false, 'rows': <Object?>[]},
      ],
};

ClientConfig _config(Map<String, Object?> homeScreen) => ClientConfig.fromJson({
  'revision': 'rev',
  'settings': const <String, Object?>{},
  'home_screen': homeScreen,
});

void main() {
  group('HomeScreenConfig', () {
    test('reads sections and rows, dropping what this version cannot draw', () {
      final config = HomeScreenConfig.tryFromJson(
        _homeScreenJson(
          sections: [
            {
              'section': 'movies',
              'rows': [
                {'id': 'a', 'kind': 'carousel', 'title': 'Future kind'},
                {'id': 'b', 'kind': 'category', 'title': 'No category'},
                {
                  'id': 'c',
                  'kind': 'category',
                  'title': 'Kids',
                  'params': {'category_id': 7},
                },
              ],
            },
            {'section': 'holodeck', 'rows': []},
            {'section': 'movies', 'rows': []},
          ],
        ),
      )!;

      expect(config.sections, hasLength(1));
      final movies = config.sectionFor(RouteNames.vod)!;
      expect(movies.rows.map((row) => row.id), ['default', 'c']);
      expect(movies.rows.last.categoryId, '7');
      expect(config.enforced, isFalse);
    });

    test('reads sports rows and yearly windows, including a new-year wrap', () {
      final config = HomeScreenConfig.tryFromJson(_homeScreenJson())!;
      final sports = config.sectionFor(RouteNames.sports)!.rows.last;
      expect(sports.kind, HomeRowKind.sportsFixtures);
      expect(sports.leagueIds, ['football/nfl']);
      expect(sports.sportsDays, 3);
      expect(sports.limit, 8);

      final xmas = config.sectionFor(RouteNames.series)!.rows.first;
      expect(xmas.isShownOn(DateTime(2026, 12, 24)), isTrue);
      expect(xmas.isShownOn(DateTime(2026, 11, 30)), isFalse);

      const wrap = HomeRowWindow(from: 1215, to: 105);
      expect(wrap.includes(DateTime(2026, 12, 31)), isTrue);
      expect(wrap.includes(DateTime(2027, 1, 3)), isTrue);
      expect(wrap.includes(DateTime(2027, 2)), isFalse);
    });

    test('round-trips through JSON', () {
      final config = HomeScreenConfig.tryFromJson(
        _homeScreenJson(mode: 'enforced'),
      )!;
      expect(HomeScreenConfig.tryFromJson(config.toJson()), config);
    });

    test('lays out the nav in the shape NavLayout reads', () {
      final layout = NavLayout.fromJson(
        HomeScreenConfig.tryFromJson(_homeScreenJson())!.navLayoutJson(),
      );
      // Sections the server leaves out (it always sends all of them) join at
      // their default place; the ones it sends keep its order.
      final sent = [RouteNames.series, RouteNames.sports, RouteNames.liveTv];
      expect(layout.order.where(sent.contains), sent);
      expect(layout.showsInNav(RouteNames.series), isFalse);
      expect(layout.showsHomeRow(RouteNames.liveTv), isFalse);
      expect(layout.order, containsAll(NavLayout.customizableRoutes));
    });
  });

  group('ViewSettingsService with a server Home screen', () {
    late ViewSettingsService service;

    setUp(() => service = ViewSettingsService());

    test('without one, Home keeps only the built-in rows', () {
      expect(service.homeRowsFor(RouteNames.series), [HomeRowSpec.builtIn]);
      expect(service.hasManagedHomeScreen, isFalse);
    });

    test(
      'a default layout applies until the user arranges their own',
      () async {
        await service.applyClientConfig(_config(_homeScreenJson()));
        expect(service.navLayoutSync.order.first, RouteNames.series);
        expect(service.isNavLayoutEnforced, isFalse);

        await service.setNavLayout(NavLayout.defaults);
        expect(service.navLayoutSync, NavLayout.defaults);

        await service.resetNavLayout();
        expect(service.navLayoutSync.order.first, RouteNames.series);
      },
    );

    test("an enforced layout wins over the user's", () async {
      await service.setNavLayout(NavLayout.defaults);
      await service.applyClientConfig(
        _config(_homeScreenJson(mode: 'enforced')),
      );

      expect(service.isNavLayoutEnforced, isTrue);
      expect(service.navLayoutSync.order.first, RouteNames.series);
    });

    test("server rows follow their window and the user's choice", () async {
      await service.applyClientConfig(_config(_homeScreenJson()));
      final december = DateTime(2026, 12, 10);
      final june = DateTime(2026, 6, 10);

      expect(
        service
            .homeRowsFor(RouteNames.series, now: december)
            .map((row) => row.id),
        ['xmas', 'default'],
      );
      expect(
        service.homeRowsFor(RouteNames.series, now: june).map((row) => row.id),
        ['default'],
      );

      await service.setHomeRowShown('xmas', shown: false);
      expect(
        service
            .homeRowsFor(RouteNames.series, now: december)
            .map((row) => row.id),
        ['default'],
      );
      expect(service.customHomeRowsFor(RouteNames.series), hasLength(1));

      await service.applyClientConfig(
        _config(_homeScreenJson(mode: 'enforced')),
      );
      expect(
        service
            .homeRowsFor(RouteNames.series, now: december)
            .map((row) => row.id),
        ['xmas', 'default'],
        reason: "an enforced layout can't be trimmed",
      );
    });

    test('notifies when only the Home screen changes', () async {
      var notifications = 0;
      service.addListener(() => notifications += 1);
      await service.applyClientConfig(_config(_homeScreenJson()));
      await service.applyClientConfig(_config(_homeScreenJson()));
      expect(notifications, 1);
      await service.applyClientConfig(
        _config(_homeScreenJson(mode: 'enforced')),
      );
      expect(notifications, 2);
    });
  });
}
