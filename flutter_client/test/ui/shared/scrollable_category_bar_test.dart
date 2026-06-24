import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

void main() {
  group('ScrollableCategoryBar', () {
    testWidgets('mouse wheel scrolls the horizontal category row', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(360, 160));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollableCategoryBar(
              tabs: List<CategoryTabData>.generate(
                18,
                (index) => CategoryTabData(
                  id: '$index',
                  name: 'Category $index',
                ),
              ),
              selectedId: '0',
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Category 0'), findsOneWidget);

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(ScrollableCategoryBar)),
          scrollDelta: const Offset(0, 420),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Category 0'), findsNothing);
      expect(find.text('Category 3'), findsOneWidget);
    });
  });
}
