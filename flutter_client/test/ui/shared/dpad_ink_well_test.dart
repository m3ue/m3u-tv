import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

void main() {
  testWidgets('DpadInkWell shows focus border on hover without taking focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: DpadInkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(8),
              child: const SizedBox(
                width: 160,
                height: 72,
                child: Center(child: Text('Hover me')),
              ),
            ),
          ),
        ),
      ),
    );

    expect(_focusBorderOpacity(tester), 0.0);
    final focusBeforeHover = FocusManager.instance.primaryFocus;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text('Hover me')));
    addTearDown(gesture.removePointer);
    await tester.pumpAndSettle();

    expect(_focusBorderOpacity(tester), 1.0);
    expect(FocusManager.instance.primaryFocus, same(focusBeforeHover));
  });
}

double _focusBorderOpacity(WidgetTester tester) {
  return tester
      .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
      .map((widget) => widget.opacity)
      .single;
}
