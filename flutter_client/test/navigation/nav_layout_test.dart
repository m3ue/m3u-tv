import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/navigation/nav_layout.dart';
import 'package:m3u_tv/navigation/route_names.dart';

void main() {
  const everything = RouteNames.mainRoutes;

  group('NavLayout', () {
    test('defaults list every destination in the original order', () {
      expect(NavLayout.defaults.navRoutes(everything), everything);
    });

    test('defaults keep the original Home rows', () {
      expect(NavLayout.defaults.homeRowRoutes, [
        RouteNames.liveTv,
        RouteNames.sports,
        RouteNames.vod,
        RouteNames.series,
        RouteNames.dvr,
      ]);
    });

    test('Home, Search, Notifications and Settings cannot be customized', () {
      for (final route in [
        RouteNames.home,
        RouteNames.search,
        RouteNames.notifications,
        RouteNames.settings,
      ]) {
        expect(NavLayout.customizableRoutes, isNot(contains(route)));
      }
    });

    test('pinned destinations hold their ends through a move and hide', () {
      final layout = NavLayout.defaults
          .moved(RouteNames.requests, -20, everything)
          .withNav(RouteNames.liveTv, shown: false);

      final routes = layout.navRoutes(everything);
      expect(routes.take(3), [
        RouteNames.home,
        RouteNames.search,
        RouteNames.requests,
      ]);
      expect(routes.skip(routes.length - 2), [
        RouteNames.notifications,
        RouteNames.settings,
      ]);
      expect(routes, isNot(contains(RouteNames.liveTv)));
    });

    test('the nav and Home switches are independent', () {
      final layout = NavLayout.defaults
          .withNav(RouteNames.vod, shown: false)
          .withHomeRow(RouteNames.requests, shown: true);

      expect(layout.showsInNav(RouteNames.vod), isFalse);
      expect(layout.showsHomeRow(RouteNames.vod), isTrue);
      expect(layout.showsInNav(RouteNames.requests), isTrue);
      expect(layout.showsHomeRow(RouteNames.requests), isTrue);
    });

    test('unavailable destinations are skipped, and keep their slot', () {
      final available = everything.where((r) => r != RouteNames.sports);
      final layout = NavLayout.defaults.moved(
        RouteNames.liveTv,
        1,
        available,
      );

      // One visible step past Movies, with Sports still second.
      expect(layout.order.take(3), [
        RouteNames.vod,
        RouteNames.sports,
        RouteNames.liveTv,
      ]);
      expect(layout.navRoutes(available), isNot(contains(RouteNames.sports)));
    });

    test('a move past either end stops there', () {
      final first = NavLayout.defaults.order.first;
      expect(
        identical(
          NavLayout.defaults.moved(first, -1, everything),
          NavLayout.defaults,
        ),
        isTrue,
      );
    });

    test('survives a JSON round trip', () {
      final layout = NavLayout.defaults
          .moved(RouteNames.dvr, -2, everything)
          .withNav(RouteNames.series, shown: false)
          .withHomeRow(RouteNames.aiostreams, shown: true);

      expect(NavLayout.fromJson(layout.toJson()), layout);
    });

    test('bad stored values fall back to defaults', () {
      expect(NavLayout.fromJson(null), NavLayout.defaults);
      expect(NavLayout.fromJson('nope'), NavLayout.defaults);
      expect(NavLayout.fromJson(const <String, Object?>{}), NavLayout.defaults);
    });

    test('drops routes it does not know, and pinned ones', () {
      final layout = NavLayout.fromJson(const {
        'order': ['/gone', RouteNames.home, RouteNames.vod, RouteNames.vod],
        'navHidden': ['/gone', RouteNames.settings],
        'home': {'/gone': true, RouteNames.vod: 'yes'},
      });

      expect(layout.order.toSet(), NavLayout.customizableRoutes.toSet());
      expect(layout.order.length, NavLayout.customizableRoutes.length);
      expect(layout.hiddenFromNav, isEmpty);
      expect(layout.homeRowChoices, isEmpty);
    });

    test('a destination new to the stored order joins at its default spot', () {
      final layout = NavLayout.fromJson(const {
        'order': [
          RouteNames.series,
          RouteNames.liveTv,
          RouteNames.vod,
          RouteNames.dvr,
          RouteNames.aiostreams,
          RouteNames.requests,
        ],
      });

      // Sports follows Live TV, its default neighbor.
      expect(layout.order.take(3), [
        RouteNames.series,
        RouteNames.liveTv,
        RouteNames.sports,
      ]);
    });
  });
}
