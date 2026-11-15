import 'package:dpad/dpad.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // Rows remember their last card app-wide (by title); start each test clean.
  setUp(DpadRegionState.clearPersistentMemory);

  /// Three rows: [first] cards, a short middle row (one card and View all),
  /// then [last] cards. Each card's focus node is keyed '<row>-<index>'.
  Future<Map<String, FocusNode>> pumpRows(
    WidgetTester tester, {
    int first = 6,
    int last = 6,
  }) async {
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final nodes = <String, FocusNode>{};
    FocusNode node(String id) => nodes.putIfAbsent(
      id,
      () => FocusNode(debugLabel: id),
    );
    addTearDown(() {
      for (final focusNode in nodes.values) {
        focusNode.dispose();
      }
    });

    Widget row(String id, int count, {bool viewAll = false}) =>
        MediaPreviewSection.builder(
          title: id,
          emptyLabel: 'None',
          itemCount: count,
          baseCardWidth: 200,
          baseCardHeight: 120,
          viewAll: viewAll
              ? MediaPreviewItem(
                  title: 'View All',
                  fallbackIcon: Icons.arrow_forward,
                  onTap: () {},
                )
              : null,
          itemBuilder: (context, index, size, {required autofocus}) =>
              DpadFocusable(
                focusNode: node('$id-$index'),
                child: SizedBox.fromSize(size: size),
              ),
        );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => Dpad(child: child!),
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row('top', first),
              row('short', 1, viewAll: true),
              row('bottom', last),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return nodes;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('Down from far along a row stops on a short row below', (
    tester,
  ) async {
    final nodes = await pumpRows(tester);
    nodes['top-4']!.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(nodes['short-0']!.hasFocus || _viewAllFocused(), isTrue);
    expect(nodes['bottom-4']!.hasFocus, isFalse);

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(
      nodes.entries.where((entry) => entry.value.hasFocus).single.key,
      startsWith('bottom-'),
    );
  });

  testWidgets('Up from far along a row stops on a short row above', (
    tester,
  ) async {
    final nodes = await pumpRows(tester);
    nodes['bottom-4']!.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(nodes['short-0']!.hasFocus || _viewAllFocused(), isTrue);
    expect(nodes['top-4']!.hasFocus, isFalse);
  });

  testWidgets('rows of the same length still move straight down', (
    tester,
  ) async {
    final nodes = await pumpRows(tester);
    nodes['short-0']!.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(nodes['bottom-0']!.hasFocus, isTrue);
  });
}

/// Whether focus sits on a card that isn't one of the keyed ones: the short
/// row's View all.
bool _viewAllFocused() {
  final focused = FocusManager.instance.primaryFocus;
  return focused != null &&
      focused.debugLabel?.contains('-') != true &&
      focused.context
              ?.findAncestorWidgetOfExactType<MediaPreviewSection>()
              ?.title ==
          'short';
}
