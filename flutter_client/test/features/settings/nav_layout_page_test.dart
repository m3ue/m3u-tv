import 'package:dpad/dpad.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/settings/sections/nav_layout_page.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/nav_layout.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/app_switch.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late ViewSettingsService service;

  /// Opens the page over a host route, so leaving it is observable.
  Future<void> pumpPage(
    WidgetTester tester, {
    List<String>? available,
    bool usesRemote = true,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    service = ViewSettingsService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          availableMainRoutesProvider.overrideWith(
            (_) => available ?? RouteNames.mainRoutes,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: NavLayoutPage(
                        service: service,
                        usesRemote: usesRemote,
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  double rowTop(WidgetTester tester, String label) =>
      tester.getTopLeft(find.text(label)).dy;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  bool pageIsOpen() => find.byType(NavLayoutPage).evaluate().isNotEmpty;

  testWidgets('every focus border sits inside the rounded group', (
    tester,
  ) async {
    await pumpPage(tester);

    final group = tester.getRect(
      find
          .ancestor(
            of: find.byType(ReorderableListView),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    final focusables = find.byType(DpadFocusable);
    expect(focusables, findsWidgets);
    for (final element in focusables.evaluate()) {
      if (element.findAncestorWidgetOfExactType<ReorderableListView>() ==
          null) {
        continue;
      }
      final rect = (element.renderObject! as RenderBox).paintBounds.shift(
        (element.renderObject! as RenderBox).localToGlobal(Offset.zero),
      );
      // Past the corner's curve: a radius 14 clip cuts nothing beyond 4 here.
      expect(rect.left - group.left, greaterThanOrEqualTo(4));
      expect(group.right - rect.right, greaterThanOrEqualTo(4));
      expect(rect.top - group.top, greaterThanOrEqualTo(4));
      expect(group.bottom - rect.bottom, greaterThanOrEqualTo(4));
    }
  });

  for (final textScale in [1.0, 1.5]) {
    testWidgets('switch focus areas match the row height at $textScale', (
      tester,
    ) async {
      await pumpPage(tester, textScale: textScale);

      final heights = {
        for (final element in find.byType(DpadFocusable).evaluate())
          if (element.findAncestorWidgetOfExactType<ReorderableListView>() !=
              null)
            (element.renderObject! as RenderBox).size.height,
      };
      expect(heights, hasLength(1));
    });
  }

  testWidgets('the hint uses the larger base size and follows app scale', (
    tester,
  ) async {
    await pumpPage(tester, textScale: 1.5);

    const hint =
        'Press OK on a row to pick it up, move it with Up and Down, then '
        'press OK to drop it. Back cancels.';
    final context = tester.element(find.byType(NavLayoutPage));
    expect(
      tester.widget<Text>(find.text(hint)).style?.fontSize,
      Theme.of(context).textTheme.bodyMedium?.fontSize,
    );
    expect(
      tester.renderObject<RenderParagraph>(find.text(hint)).textScaler,
      const TextScaler.linear(1.5),
    );
  });

  testWidgets('lists only the customizable, available destinations', (
    tester,
  ) async {
    await pumpPage(
      tester,
      available: RouteNames.mainRoutes
          .where((route) => route != RouteNames.dvr)
          .toList(),
    );

    for (final label in ['Live TV', 'Sports', 'Movies', 'Series']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('DVR'), findsNothing);
    expect(find.text('Search'), findsNothing);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('OK picks a row up, Down moves it, and OK saves on drop', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(rowTop(tester, 'Live TV'), lessThan(rowTop(tester, 'Sports')));

    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(rowTop(tester, 'Sports'), lessThan(rowTop(tester, 'Live TV')));
    expect(service.navLayoutSync, NavLayout.defaults, reason: 'not dropped');

    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);

    expect(service.navLayoutSync.order.take(3), [
      RouteNames.sports,
      RouteNames.vod,
      RouteNames.liveTv,
    ]);
    expect(pageIsOpen(), isTrue);
  });

  testWidgets('the moved row keeps focus through several moves', (
    tester,
  ) async {
    await pumpPage(tester);

    await press(tester, LogicalKeyboardKey.select);
    for (var i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    await press(tester, LogicalKeyboardKey.select);

    expect(service.navLayoutSync.order.indexOf(RouteNames.liveTv), 3);
  });

  testWidgets('Back cancels a grab and only a second Back leaves', (
    tester,
  ) async {
    await pumpPage(tester);

    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowDown);

    // What AppShell's handler ends up doing for either delivery path.
    final context = tester.element(find.byType(NavLayoutPage));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    expect(pageIsOpen(), isTrue);
    expect(rowTop(tester, 'Live TV'), lessThan(rowTop(tester, 'Sports')));
    expect(service.navLayoutSync, NavLayout.defaults);

    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    expect(pageIsOpen(), isFalse);
  });

  testWidgets('left and right do nothing while a row is grabbed', (
    tester,
  ) async {
    await pumpPage(tester);

    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);

    expect(service.navLayoutSync.order.first, RouteNames.sports);
  });

  testWidgets('Right reaches the switches, and OK flips them', (tester) async {
    await pumpPage(tester);

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(service.navLayoutSync.showsInNav(RouteNames.liveTv), isFalse);
    expect(service.navLayoutSync.showsHomeRow(RouteNames.liveTv), isTrue);

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(service.navLayoutSync.showsHomeRow(RouteNames.liveTv), isFalse);
  });

  testWidgets('tapping a switch saves it', (tester) async {
    await pumpPage(tester, usesRemote: false);

    await tester.tap(find.byType(AppSwitch).first);
    await tester.pumpAndSettle();

    expect(service.navLayoutSync.showsInNav(RouteNames.liveTv), isFalse);
  });

  testWidgets('tapping a row does not pick it up', (tester) async {
    await pumpPage(tester, usesRemote: false);

    await tester.tap(find.text('Live TV'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(NavLayoutPage));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    expect(pageIsOpen(), isFalse);
  });

  testWidgets('dragging the handle moves the row and saves', (tester) async {
    await pumpPage(tester, usesRemote: false);

    final handle = find.byIcon(Icons.drag_handle).first;
    final rowHeight = rowTop(tester, 'Sports') - rowTop(tester, 'Live TV');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(Offset(0, rowHeight * 1.6));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(service.navLayoutSync.order.first, isNot(RouteNames.liveTv));
    expect(
      rowTop(tester, 'Sports'),
      lessThan(rowTop(tester, 'Live TV')),
    );
  });

  testWidgets('Reset restores the defaults after confirming', (tester) async {
    await pumpPage(tester, usesRemote: false);
    await tester.tap(find.byType(AppSwitch).first);
    await tester.pumpAndSettle();
    expect(service.navLayoutSync, isNot(NavLayout.defaults));

    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(service.navLayoutSync, NavLayout.defaults);
  });
}
