import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsData, SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import 'package:m3u_tv/shared/tvos_scroll_semantics.dart';

Widget _strip({ScrollBehavior? behavior}) => MaterialApp(
  scrollBehavior: behavior,
  home: Center(
    child: SizedBox(
      width: 400,
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemExtent: 100,
        itemCount: 50,
        itemBuilder: (context, index) => Text('$index'),
      ),
    ),
  ),
);

/// The ListView's scroll node - the one carrying a scroll position.
SemanticsData _scrollNode(WidgetTester tester) {
  SemanticsData? found;
  bool visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.scrollPosition != null) {
      found = data;
      return false;
    }
    node.visitChildren(visit);
    return found == null;
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return found!;
}

void main() {
  group('TvosScrollBehavior', () {
    testWidgets(
      'scrollables drop implicit scrolling (no native UIScrollView mirror, '
      'no scrollToOffset) but keep their own scroll actions and physics',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(_strip(behavior: const TvosScrollBehavior()));

        final data = _scrollNode(tester);
        expect(data.flagsCollection.hasImplicitScrolling, isFalse);
        expect(data.hasAction(SemanticsAction.scrollToOffset), isFalse);
        expect(data.hasAction(SemanticsAction.scrollLeft), isTrue);

        await tester.drag(find.byType(ListView), const Offset(-300, 0));
        await tester.pumpAndSettle();
        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable))
              .position
              .pixels,
          greaterThan(0),
        );
        semantics.dispose();
      },
    );

    testWidgets(
      'control: the stock behaviour exposes implicit scrolling and '
      'scrollToOffset (what the tvOS focus engine drives)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(_strip());

        final data = _scrollNode(tester);
        expect(data.flagsCollection.hasImplicitScrolling, isTrue);
        expect(data.hasAction(SemanticsAction.scrollToOffset), isTrue);
        semantics.dispose();
      },
    );
  });

  group('ignoreNativeScrollToOffset', () {
    test('drops scrollToOffset and forwards every other action', () {
      final forwarded = <SemanticsAction>[];
      final guarded = ignoreNativeScrollToOffset(
        (event) => forwarded.add(event.type),
      );

      guarded(
        const SemanticsActionEvent(
          type: SemanticsAction.scrollToOffset,
          viewId: 0,
          nodeId: 1,
        ),
      );
      guarded(
        const SemanticsActionEvent(
          type: SemanticsAction.tap,
          viewId: 0,
          nodeId: 1,
        ),
      );
      guarded(
        const SemanticsActionEvent(
          type: SemanticsAction.scrollLeft,
          viewId: 0,
          nodeId: 1,
        ),
      );

      expect(forwarded, [SemanticsAction.tap, SemanticsAction.scrollLeft]);
    });

    test('tolerates a null handler', () {
      ignoreNativeScrollToOffset(null)(
        const SemanticsActionEvent(
          type: SemanticsAction.tap,
          viewId: 0,
          nodeId: 1,
        ),
      );
    });
  });
}
