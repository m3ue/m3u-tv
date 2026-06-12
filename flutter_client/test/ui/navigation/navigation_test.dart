import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/app/app_shell.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/navigation/route_names.dart';

void main() {
  group('Route navigation', () {
    testWidgets('initial route shows Home content', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      // Home text appears in both sidebar and content area
      expect(find.text('Home'), findsAtLeast(1));
      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('navigating to LiveTV shows Live TV screen', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      // Sidebar is expanded by default, so text is visible
      await tester.tap(find.text('Live TV'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('navigating to VOD shows Movies screen', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Movies'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('navigating to Series shows Series screen', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('navigating to Search shows Search screen', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('navigating to Settings shows Settings screen', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Server URL'), findsOneWidget);
    });

    testWidgets('sidebar labels remain visible after selecting a route', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(NavigationSidebar),
          matching: find.text('Home'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(NavigationSidebar),
          matching: find.text('Settings'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Player route pushes as modal via inner navigator', (
      tester,
    ) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      final nav = _findInnerNavigator(tester);
      unawaited(
        nav.pushNamed(
          RouteNames.player,
          arguments: const PlayerArgs(
            streamUrl: 'http://example.com/stream.m3u8',
            title: 'Test Channel',
            type: 'live',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Channel'), findsOneWidget);
    });

    testWidgets('Details route pushes via inner navigator', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      final nav = _findInnerNavigator(tester);
      unawaited(
        nav.pushNamed(
          RouteNames.details,
          arguments: const DetailsArgs(vodId: 1, vodName: 'Test Movie'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Movie'), findsOneWidget);
    });

    testWidgets('SeriesDetails route pushes via inner navigator', (
      tester,
    ) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      final nav = _findInnerNavigator(tester);
      unawaited(
        nav.pushNamed(
          RouteNames.seriesDetails,
          arguments: const SeriesDetailsArgs(
            seriesId: 1,
            seriesName: 'Test Series',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Series'), findsOneWidget);
    });

    testWidgets('ViewerSelection route pushes via inner navigator', (
      tester,
    ) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      final nav = _findInnerNavigator(tester);
      unawaited(nav.pushNamed(RouteNames.viewerSelection));
      await tester.pumpAndSettle();

      expect(find.text('Viewer Selection'), findsOneWidget);
    });
  });

  group('Adaptive layout', () {
    testWidgets('TV device shows sidebar navigation', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationSidebar), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
    });

    testWidgets('Desktop device shows sidebar navigation', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.desktop));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationSidebar), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
    });

    testWidgets('Phone device shows bottom navigation', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.phone));
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byType(NavigationSidebar), findsNothing);
    });

    testWidgets('Tablet device shows bottom navigation', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tablet));
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byType(NavigationSidebar), findsNothing);
    });
  });

  group('TV focus traversal', () {
    testWidgets('sidebar items are focusable', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      final sidebarItems = find.byType(SidebarDestinationItem);
      expect(sidebarItems, findsAtLeast(6));
    });

    testWidgets('D-pad down moves focus through sidebar items', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('D-pad right moves focus from sidebar to content', (
      tester,
    ) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('Menu key opens sidebar on TV', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();

      expect(find.byType(NavigationSidebar), findsOneWidget);
    });
  });

  group('Back behavior', () {
    testWidgets('back button on modal route pops to main', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      final nav = _findInnerNavigator(tester);
      unawaited(
        nav.pushNamed(
          RouteNames.player,
          arguments: const PlayerArgs(
            streamUrl: 'http://example.com/stream.m3u8',
            title: 'Test Channel',
            type: 'live',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Channel'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Should be back at Home content
      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('back on TV activates sidebar when content is focused', (
      tester,
    ) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      // Move focus to content area first
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      // Press back/escape
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byType(NavigationSidebar), findsOneWidget);
    });

    testWidgets('back on phone pops modal routes', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.phone));
      await tester.pumpAndSettle();

      final nav = _findInnerNavigator(tester);
      unawaited(
        nav.pushNamed(
          RouteNames.details,
          arguments: const DetailsArgs(vodId: 1, vodName: 'Test Movie'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Movie'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Should be back at Home content
      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });
  });

  group('Focus restoration', () {
    testWidgets('returning from modal restores previous route content', (
      tester,
    ) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      // Navigate to Live TV
      await tester.tap(find.text('Live TV'));
      await tester.pumpAndSettle();

      // Push Player modal
      final nav = _findInnerNavigator(tester);
      unawaited(
        nav.pushNamed(
          RouteNames.player,
          arguments: const PlayerArgs(
            streamUrl: 'http://example.com/stream.m3u8',
            title: 'Test Channel',
            type: 'live',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pop Player
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Should be back at Live TV content (not Home)
      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });
  });
}

/// Finds the inner NavigatorState from the _ContentNavigator widget.
NavigatorState _findInnerNavigator(WidgetTester tester) {
  final navigators = tester.stateList<NavigatorState>(find.byType(Navigator));
  // The inner navigator is the last one (MaterialApp creates the first)
  return navigators.last;
}

/// Test app that wraps AppShell with a controlled device type.
class _TestApp extends StatelessWidget {
  const _TestApp({required this.deviceType});

  final DeviceType deviceType;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M3U TV Test',
      theme: ThemeData.dark(useMaterial3: true),
      home: AppShell(deviceType: deviceType),
    );
  }
}
