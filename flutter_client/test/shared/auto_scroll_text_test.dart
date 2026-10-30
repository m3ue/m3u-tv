import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/auto_scroll_text.dart';

void main() {
  const style = TextStyle(fontSize: 20, height: 1);

  Future<void> pumpText(WidgetTester tester, String text) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: SizedBox(
            width: 300,
            // Loose height, like the Home spotlight's Column: the text must
            // hug its lines rather than fill the space.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: AutoScrollText(
                    key: const ValueKey('plot'),
                    text: text,
                    style: style,
                    maxLines: 3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('short text shows as is, at its own height', (tester) async {
    await pumpText(tester, 'A short plot.');

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('plot'))).height, 20);
  });

  testWidgets('long text caps at maxLines and scrolls through the rest', (
    tester,
  ) async {
    await pumpText(tester, List.filled(60, 'word').join(' '));

    expect(tester.getSize(find.byKey(const ValueKey('plot'))).height, 60);
    final scrollable = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scrollable.controller!.offset, 0);

    // Rests at the top first, then scrolls down.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 2));
    expect(scrollable.controller!.offset, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unbounded height with no maxLines shows the text in full', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 300,
              child: AutoScrollText(
                key: ValueKey('plot'),
                text: 'One line. Two lines worth of words to wrap around.',
                style: style,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('plot'))).height,
      greaterThan(0),
    );
    expect(find.textContaining('One line.'), findsOneWidget);
  });
}
