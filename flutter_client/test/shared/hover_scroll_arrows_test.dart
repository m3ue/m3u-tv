import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/hover_scroll_arrows.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Widget harness(ScrollController controller) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 120,
            child: HoverScrollArrows(
              controller: controller,
              child: ListView.builder(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemExtent: 200,
                itemCount: 20,
                itemBuilder: (_, i) => Center(child: Text('item $i')),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double opacityAround(WidgetTester tester, Finder of) {
    return tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: of, matching: find.byType(AnimatedOpacity)),
        )
        .opacity;
  }

  testWidgets('off desktop the child passes straight through, no arrows', (
    tester,
  ) async {
    // Default test platform is Android - not a desktop OS.
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    await tester.pump();

    expect(find.text('item 0'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
  });

  testWidgets(
    'on desktop, hovering reveals the right arrow and tapping it scrolls',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final controller = ScrollController();

      try {
        await tester.pumpWidget(harness(controller));
        await tester.pumpAndSettle();

        final rightArrow = find.byIcon(Icons.chevron_right);
        final leftArrow = find.byIcon(Icons.chevron_left);

        // Arrows are in the tree but transparent until the pointer is over the
        // strip, and the left one also needs somewhere to scroll back to.
        expect(rightArrow, findsOneWidget);
        expect(leftArrow, findsOneWidget);
        expect(opacityAround(tester, rightArrow), 0.0);

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(
          location: tester.getCenter(find.byType(ListView)),
        );
        addTearDown(gesture.removePointer);
        await tester.pumpAndSettle();

        // Hovering at offset 0: right arrow shows, left stays hidden.
        expect(opacityAround(tester, rightArrow), 1.0);
        expect(opacityAround(tester, leftArrow), 0.0);

        expect(controller.offset, 0);
        await tester.tap(rightArrow);
        await tester.pumpAndSettle();

        // One press travels ~80% of the 400px viewport.
        expect(controller.offset, greaterThan(300));
        // Now there is content to the left, so that arrow lights up too.
        expect(opacityAround(tester, leftArrow), 1.0);
      } finally {
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
