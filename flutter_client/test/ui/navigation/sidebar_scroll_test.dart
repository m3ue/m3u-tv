import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/app/navigation_sidebar.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:material_ui/material_ui.dart';

const List<String> _routes = [
  RouteNames.home,
  RouteNames.search,
  RouteNames.liveTv,
  RouteNames.sports,
  RouteNames.vod,
  RouteNames.series,
  RouteNames.aiostreams,
  RouteNames.dvr,
  RouteNames.requests,
  RouteNames.notifications,
  RouteNames.settings,
];

void main() {
  late List<FocusNode> nodes;

  Future<void> pumpSidebar(
    WidgetTester tester, {
    double height = 420,
    int currentIndex = 0,
  }) async {
    await tester.binding.setSurfaceSize(Size(800, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    nodes = List.generate(_routes.length, (_) => FocusNode());
    addTearDown(() {
      for (final node in nodes) {
        node.dispose();
      }
    });
    final scope = FocusScopeNode();
    addTearDown(scope.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              NavigationSidebar(
                currentIndex: currentIndex,
                routes: _routes,
                sidebarActive: true,
                focusNodes: nodes,
                scopeNode: scope,
                onNavigate: (_) {},
                onActivateSidebar: () {},
                onDeactivateSidebar: () {},
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder destination(int index) => find.byWidgetPredicate(
    (widget) =>
        widget is SidebarDestinationItem && widget.focusNode == nodes[index],
    skipOffstage: false,
  );

  /// Whether the whole item shows inside the list, clear of the logo and of
  /// the pinned divider.
  void expectFullyVisible(WidgetTester tester, int index) {
    final rect = tester.getRect(destination(index));
    final logoBottom = tester.getBottomLeft(find.byType(SvgPicture)).dy;
    final dividerTop = tester.getTopLeft(find.byType(Divider)).dy;
    expect(
      rect.top,
      greaterThanOrEqualTo(logoBottom),
      reason: '${_routes[index]} hidden behind the logo',
    );
    if (index < 9) {
      expect(
        rect.bottom,
        lessThanOrEqualTo(dividerTop),
        reason: '${_routes[index]} hidden behind the footer',
      );
    }
  }

  List<double> shadowOpacities(WidgetTester tester) => tester
      .widgetList<AnimatedOpacity>(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_SidebarEdgeShadow',
          ),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .map((opacity) => opacity.opacity)
      .toList();

  testWidgets('the logo and footer stay put while the middle scrolls', (
    tester,
  ) async {
    await pumpSidebar(tester);
    nodes.first.requestFocus();
    await tester.pumpAndSettle();
    final logo = tester.getTopLeft(find.byType(SvgPicture));
    final settings = tester.getTopLeft(destination(10));

    for (var i = 1; i <= 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(nodes[i].hasPrimaryFocus, isTrue, reason: _routes[i]);
      expectFullyVisible(tester, i);
    }

    expect(tester.getTopLeft(find.byType(SvgPicture)), logo);
    expect(tester.getTopLeft(destination(10)), settings);
  });

  testWidgets('Up and Down walk the whole list in order, across the footer', (
    tester,
  ) async {
    await pumpSidebar(tester);
    nodes.first.requestFocus();
    await tester.pumpAndSettle();

    for (var i = 1; i < _routes.length; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(nodes[i].hasPrimaryFocus, isTrue, reason: _routes[i]);
    }
    // Stays on the last one.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(nodes.last.hasPrimaryFocus, isTrue);

    for (var i = _routes.length - 2; i >= 0; i--) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(nodes[i].hasPrimaryFocus, isTrue, reason: _routes[i]);
      expectFullyVisible(tester, i);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(nodes.first.hasPrimaryFocus, isTrue);
  });

  testWidgets('shadows mark the edges with more to scroll to', (tester) async {
    await pumpSidebar(tester);
    expect(shadowOpacities(tester), [0, 1]);

    nodes[4].requestFocus();
    await tester.pumpAndSettle();
    expect(shadowOpacities(tester), [1, 1]);

    nodes[8].requestFocus();
    await tester.pumpAndSettle();
    expect(shadowOpacities(tester), [1, 0]);
  });

  testWidgets('no shadows when everything fits', (tester) async {
    await pumpSidebar(tester, height: 1080);
    expect(shadowOpacities(tester), [0, 0]);
  });

  testWidgets('opens scrolled to the current destination', (tester) async {
    await pumpSidebar(tester, currentIndex: 8);
    expectFullyVisible(tester, 8);
  });
}
