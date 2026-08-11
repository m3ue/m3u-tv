import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  group(
    'Option D: long-press fires at threshold; inherited hold is ignored',
    () {
      testWidgets('a) long-press fires AT the threshold, mid-hold', (
        tester,
      ) async {
        var longTapCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: Center(
                child: DpadInkWell(
                  autofocus: true,
                  onLongTap: () => longTapCount++,
                  borderRadius: BorderRadius.circular(8),
                  child: const SizedBox(
                    width: 160,
                    height: 72,
                    child: Center(child: Text('Hold me')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        // NOTE: this asserts onLongTap fires at the threshold, but it CANNOT
        // detect a deferred dispatch. pump() always runs a full frame and
        // flushes post-frame callbacks registered during it, so an
        // addPostFrameCallback dispatch passes here while failing on a real
        // device, where nothing schedules a frame during a hold and the menu
        // waits for the release rebuild. Verified: reintroducing the deferral
        // keeps this test green. Device testing is the only guard for that.
        await tester.pump(const Duration(milliseconds: 600));

        expect(
          longTapCount,
          1,
          reason:
              'onLongTap must fire AT the threshold, mid-hold, without waiting '
              'for a further frame — otherwise the menu only opens on release',
        );

        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
      });

      testWidgets('b) short press fires onTap, not onLongTap', (tester) async {
        var tapCount = 0;
        var longTapCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: Center(
                child: DpadInkWell(
                  autofocus: true,
                  onTap: () => tapCount++,
                  onLongTap: () => longTapCount++,
                  borderRadius: BorderRadius.circular(8),
                  child: const SizedBox(
                    width: 160,
                    height: 72,
                    child: Center(child: Text('Tap me')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();

        expect(tapCount, 1);
        expect(longTapCount, 0);
      });

      testWidgets(
        'c) REGRESSION: autofocused child of mid-hold menu ignores inherited '
        'select; fires on fresh press',
        (tester) async {
          var innerTapCount = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(useMaterial3: true),
              home: _LongPressMenuHost(
                innerTapRecorder: () => innerTapCount++,
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Hold select on the outer item. At ~500ms the dpad long-press
          // timer fires and onLongTap opens a fresh route containing an
          // autofocused inner DpadInkWell. The user is still holding.
          await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pumpAndSettle();

          expect(
            find.text('Inner'),
            findsOneWidget,
            reason:
                'menu must open at threshold with the inner item autofocused',
          );

          // Android TV's auto-repeat delivers fresh KeyDownEvents (not
          // KeyRepeatEvent). The autofocused inner item must NOT activate on
          // a key-down whose matching key-up it never observed.
          await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          expect(
            innerTapCount,
            0,
            reason: 'REGRESSION: inherited select hold must not activate inner',
          );

          // Second auto-repeat tick while still held — also must not fire.
          await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          expect(innerTapCount, 0);

          // Release. The held key is now released; the guard disarms.
          await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();

          // A fresh press after release must activate the inner item.
          await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();

          expect(
            innerTapCount,
            1,
            reason: 'fresh press after release must activate the inner item',
          );
        },
      );

      testWidgets('d) widget mounted with NO select held is not armed', (
        tester,
      ) async {
        var tapCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: Center(
                child: DpadInkWell(
                  autofocus: true,
                  onTap: () => tapCount++,
                  borderRadius: BorderRadius.circular(8),
                  child: const SizedBox(
                    width: 160,
                    height: 72,
                    child: Center(child: Text('Tap me')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          DpadInkWell.debugActiveGlobalHandlers,
          0,
          reason:
              'no key held at mount → no global handler should be registered',
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();

        expect(
          tapCount,
          1,
          reason: 'normal short press must fire onTap immediately',
        );
        expect(
          DpadInkWell.debugActiveGlobalHandlers,
          0,
          reason: 'a normal press must not leave a handler registered',
        );
      });

      testWidgets(
        'd2) an unrelated select-mapped key press/release does not disarm '
        'the guard while the originally-held key is still down',
        (tester) async {
          var innerTapCount = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(useMaterial3: true),
              home: _LongPressMenuHost(
                innerTapRecorder: () => innerTapCount++,
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pumpAndSettle();
          expect(find.text('Inner'), findsOneWidget);

          // A different select-mapped key (e.g. a connected keyboard's
          // Enter) is pressed and released while select is still held.
          await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();

          // The originally-held select key is still down; auto-repeat must
          // still be ignored.
          await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          expect(
            innerTapCount,
            0,
            reason:
                'an unrelated select-mapped key up must not disarm the '
                'guard while the original held key is still down',
          );

          await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
        },
      );

      testWidgets('e) touch long press still fires onLongTap at threshold', (
        tester,
      ) async {
        var longTapCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: Center(
                child: DpadInkWell(
                  onLongTap: () => longTapCount++,
                  borderRadius: BorderRadius.circular(8),
                  child: const SizedBox(
                    width: 160,
                    height: 72,
                    child: Center(child: Text('Touch me')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.longPress(find.byType(DpadInkWell));
        await tester.pumpAndSettle();

        expect(longTapCount, 1);
      });

      testWidgets('f) global handler is removed on dispose (no leak)', (
        tester,
      ) async {
        final baseline = DpadInkWell.debugActiveGlobalHandlers;

        // Pre-hold select BEFORE mounting so didChangeDependencies observes a
        // held key and arms the guard.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: Center(
                child: DpadInkWell(
                  autofocus: true,
                  onTap: () {},
                  borderRadius: BorderRadius.circular(8),
                  child: const SizedBox(width: 160, height: 72),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          DpadInkWell.debugActiveGlobalHandlers,
          baseline + 1,
          reason: 'widget mounted with select held should register a handler',
        );

        // Tear down the widget tree. dispose() must unconditionally release
        // any handler it registered.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        expect(
          DpadInkWell.debugActiveGlobalHandlers,
          baseline,
          reason: 'dispose must release the global handler — leak guard',
        );

        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
      });
    },
  );
}

class _LongPressMenuHost extends StatefulWidget {
  const _LongPressMenuHost({required this.innerTapRecorder});

  final VoidCallback innerTapRecorder;

  @override
  State<_LongPressMenuHost> createState() => _LongPressMenuHostState();
}

class _LongPressMenuHostState extends State<_LongPressMenuHost> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: DpadInkWell(
          autofocus: true,
          onLongTap: () => _openMenu(context),
          borderRadius: BorderRadius.circular(8),
          child: const SizedBox(
            width: 160,
            height: 72,
            child: Center(child: Text('Outer')),
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context) {
    // showDialog pushes a new route. The inner DpadInkWell mounts inside
    // a fresh element tree (a fresh Navigator overlay), so its State runs
    // initState + didChangeDependencies — the same shape as a real TV
    // context menu in production.
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: DpadInkWell(
            autofocus: true,
            onTap: () {
              widget.innerTapRecorder();
              Navigator.of(dialogContext).pop();
            },
            borderRadius: BorderRadius.circular(8),
            child: const SizedBox(
              width: 160,
              height: 72,
              child: Center(child: Text('Inner')),
            ),
          ),
        );
      },
    );
  }
}

double _focusBorderOpacity(WidgetTester tester) {
  return tester
      .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
      .map((widget) => widget.opacity)
      .single;
}
