import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/desktop_fullscreen_service.dart';

class _FakeWindow implements FullscreenWindow {
  bool fullscreen = false;
  final List<bool> requests = <bool>[];

  @override
  Future<bool> isFullScreen() async => fullscreen;

  @override
  Future<void> setFullScreen({required bool fullscreen}) async {
    requests.add(fullscreen);
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

void main() {
  late _FakeWindow window;
  late DesktopFullscreenService service;
  late int backCount;

  Future<void> pumpPage(WidgetTester tester) async {
    window = _FakeWindow();
    service = DesktopFullscreenService(
      window: window,
      altEnterToggles: true,
      transitionTimeout: const Duration(seconds: 1),
    );
    await service.install();
    addTearDown(service.dispose);
    backCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _BackIntent: CallbackAction<_BackIntent>(
                onInvoke: (_) => backCount++,
              ),
            },
            child: const Focus(autofocus: true, child: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('F11 toggles and follows the window enter/leave events', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    expect(window.requests, [true]);
    expect(service.isTransitioning, isTrue);
    expect(service.isFullscreen, isFalse);

    service.onWindowEnterFullScreen();
    expect(service.isTransitioning, isFalse);
    expect(service.isFullscreen, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    service.onWindowLeaveFullScreen();
    expect(window.requests, [true, false]);
    expect(service.isFullscreen, isFalse);
  });

  testWidgets('ignores toggles while a transition is in flight', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    expect(window.requests, [true]);
    expect(backCount, 0);

    // Let the pending transition settle so no timer outlives the test.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Escape leaves fullscreen without going Back', (tester) async {
    await pumpPage(tester);
    unawaited(service.toggle());
    service.onWindowEnterFullScreen();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    expect(window.requests, [true, false]);
    expect(backCount, 0);

    // Let the pending transition settle so no timer outlives the test.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Escape is Back when not fullscreen', (tester) async {
    await pumpPage(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    expect(window.requests, isEmpty);
    expect(backCount, 1);
  });

  testWidgets('Alt+Enter toggles when enabled', (tester) async {
    await pumpPage(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(window.requests, [true]);

    // Let the pending transition settle so no timer outlives the test.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('follows a fullscreen change made outside the app', (
    tester,
  ) async {
    await pumpPage(tester);
    var notified = 0;
    // macOS green button / View > Enter Full Screen.
    service
      ..addListener(() => notified++)
      ..onWindowEnterFullScreen();

    expect(service.isFullscreen, isTrue);
    expect(notified, 1);
    expect(window.requests, isEmpty);
  });

  testWidgets('resyncs from the window when no event arrives', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    expect(service.isTransitioning, isTrue);

    // The window never confirmed, and is still windowed.
    await tester.pump(const Duration(seconds: 2));

    expect(service.isTransitioning, isFalse);
    expect(service.isFullscreen, isFalse);
  });
}
