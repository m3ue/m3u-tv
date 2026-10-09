import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/app/app_shell.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/route_names.dart';

void main() {
  Widget sidebar(List<String> routes, List<FocusNode> nodes) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Row(
          children: [
            NavigationSidebar(
              currentIndex: 0,
              routes: routes,
              sidebarActive: true,
              focusNodes: nodes,
              scopeNode: FocusScopeNode(),
              onNavigate: (_) {},
              onActivateSidebar: () {},
              onDeactivateSidebar: () {},
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    );
  }

  /// Opacity of each item's focus ring (the last AnimatedOpacity in it).
  List<double> ringOpacities(WidgetTester tester) => [
    for (final item in find.byType(SidebarDestinationItem).evaluate())
      tester
          .widgetList<AnimatedOpacity>(
            find.descendant(
              of: find.byWidget(item.widget),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .last
          .opacity,
  ];

  testWidgets(
    'only the focused item shows a focus ring while the mouse rests on another',
    (tester) async {
      const routes = [
        RouteNames.home,
        RouteNames.dvr,
        RouteNames.requests,
        RouteNames.notifications,
        RouteNames.settings,
      ];
      final nodes = List.generate(routes.length, (_) => FocusNode());
      await tester.pumpWidget(sidebar(routes, nodes));
      await tester.pumpAndSettle();

      // The pointer rests over DVR, as on desktop when the sidebar opened on
      // mouse enter.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byType(SidebarDestinationItem).at(1)),
      );
      await tester.pumpAndSettle();

      // The keyboard/D-pad moves focus down to Settings.
      nodes.last.requestFocus();
      await tester.pumpAndSettle();

      final rings = ringOpacities(tester);
      expect(rings, [0.0, 0.0, 0.0, 0.0, 1.0]);
    },
  );

  testWidgets(
    'only the focused item shows a focus ring after a gated destination appears',
    (tester) async {
      // Start without DVR, as the app does before it knows DVR is enabled.
      var routes = [
        RouteNames.home,
        RouteNames.search,
        RouteNames.notifications,
        RouteNames.settings,
      ];
      final nodes = List.generate(routes.length, (_) => FocusNode());
      await tester.pumpWidget(sidebar(routes, nodes));

      // DVR shows up: AppShell grows its focus node list in place.
      routes = [
        RouteNames.home,
        RouteNames.search,
        RouteNames.dvr,
        RouteNames.notifications,
        RouteNames.settings,
      ];
      nodes.add(FocusNode());
      await tester.pumpWidget(sidebar(routes, List.of(nodes)));
      await tester.pumpAndSettle();

      for (var i = 0; i < routes.length; i++) {
        nodes[i].requestFocus();
        await tester.pumpAndSettle();
        final rings = ringOpacities(tester);
        expect(
          rings.where((o) => o == 1.0).length,
          1,
          reason: 'focus on ${routes[i]}: $rings',
        );
        expect(rings[i], 1.0, reason: 'focus on ${routes[i]}: $rings');
      }
    },
  );
}
