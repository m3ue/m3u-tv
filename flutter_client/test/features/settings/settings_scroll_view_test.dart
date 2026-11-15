import 'package:dpad/dpad.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  /// A settings sub-page, opened the way the settings list opens one.
  Future<void> pumpSubpage(WidgetTester tester, WidgetBuilder builder) async {
    tester.view
      ..physicalSize = const Size(800, 400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Dpad(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => pushSettingsSubpage<void>(
                  context,
                  title: (_) => 'Page',
                  builder: builder,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  ScrollPosition pagePosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(SettingsScrollView),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    int times = 1,
  }) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  Widget card(String label) => SettingsCard(
    child: SizedBox(height: 150, child: Text(label)),
  );

  Widget rows({int count = 6}) => SettingsGroup(
    children: [
      for (var i = 0; i < count; i++)
        SettingsRow(title: 'Row $i', autofocus: i == 0, onTap: () {}),
    ],
  );

  testWidgets('going back up shows the card above the first row', (
    tester,
  ) async {
    await pumpSubpage(
      tester,
      (_) => Column(children: [card('Top card'), rows()]),
    );
    final position = pagePosition(tester);

    await press(tester, LogicalKeyboardKey.arrowDown, times: 5);
    expect(position.pixels, greaterThan(150));

    await press(tester, LogicalKeyboardKey.arrowUp, times: 5);
    expect(position.pixels, 0);
  });

  testWidgets('going down shows the card below the last row', (tester) async {
    await pumpSubpage(
      tester,
      (_) => Column(children: [rows(), card('Bottom card')]),
    );
    final position = pagePosition(tester);

    await press(tester, LogicalKeyboardKey.arrowDown, times: 5);

    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('rows between the first and last stay a partial reveal', (
    tester,
  ) async {
    await pumpSubpage(
      tester,
      (_) => Column(children: [card('Top card'), rows(), card('Bottom card')]),
    );
    final position = pagePosition(tester);

    await press(tester, LogicalKeyboardKey.arrowDown, times: 5);
    await press(tester, LogicalKeyboardKey.arrowUp, times: 2);

    expect(position.pixels, greaterThan(0));
    expect(position.pixels, lessThan(position.maxScrollExtent));
  });

  testWidgets('never scrolls the first row off screen to reach the top', (
    tester,
  ) async {
    await pumpSubpage(
      tester,
      (_) => Column(
        children: [
          SettingsCard(child: Container(height: 900)),
          rows(count: 2),
        ],
      ),
    );
    final position = pagePosition(tester);

    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowUp);

    expect(position.pixels, greaterThan(0));
    final focused = FocusManager.instance.primaryFocus!.rect;
    expect(focused.bottom, lessThanOrEqualTo(400));
    expect(focused.top, greaterThanOrEqualTo(0));
  });

  testWidgets('leaves the only item on the page where its reveal put it', (
    tester,
  ) async {
    // Opening the page is a tap here, which would skip this as touch input.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    await pumpSubpage(
      tester,
      (_) => Column(
        children: [
          SettingsCard(child: Container(height: 900)),
          rows(count: 1),
          card('Bottom card'),
        ],
      ),
    );
    final position = pagePosition(tester);

    expect(position.pixels, greaterThan(0));
    expect(position.pixels, lessThan(position.maxScrollExtent));
    // Its reveal leaves a gap; pushing towards the top would close it.
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    expect(
      FocusManager.instance.primaryFocus!.rect.bottom,
      lessThan(viewport.bottom - 1),
    );
  });

  testWidgets('leaves touch input alone', (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    await pumpSubpage(
      tester,
      (_) => Column(children: [card('Top card'), rows()]),
    );
    final position = pagePosition(tester);

    await press(tester, LogicalKeyboardKey.arrowDown, times: 5);
    await press(tester, LogicalKeyboardKey.arrowUp, times: 5);

    expect(position.pixels, greaterThan(0));
  });
}
