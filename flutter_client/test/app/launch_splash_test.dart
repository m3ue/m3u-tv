import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/app/launch_splash.dart';

ui.Picture _logo() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawCircle(const Offset(50, 50), 50, Paint());
  return recorder.endRecording();
}

Widget _host(
  LaunchSplashController controller, {
  Duration maxHold = const Duration(seconds: 10),
  double? launchDensity,
}) => LaunchSplashHost(
  controller: controller,
  logo: _logo(),
  logoViewBox: const Size(100, 100),
  logoSize: 102,
  launchDensity: launchDensity,
  maxHold: maxHold,
);

double _paintedLogoSize(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is LaunchSplashPainter,
    ),
  );
  return (paint.painter! as LaunchSplashPainter).logoSize;
}

Finder get _splash => find.byType(AbsorbPointer);

/// Mirrors AppShell starting boot() from initState: flips booting on
/// mid-build of the app's first frame.
class _BootingApp extends StatefulWidget {
  const _BootingApp(this.booting);

  final ValueNotifier<bool> booting;

  @override
  State<_BootingApp> createState() => _BootingAppState();
}

class _BootingAppState extends State<_BootingApp> {
  @override
  void initState() {
    super.initState();
    widget.booting.value = true;
  }

  @override
  Widget build(BuildContext context) => const Text('app');
}

void main() {
  testWidgets('keeps the splash up while booting, then fades it out', (
    tester,
  ) async {
    final controller = LaunchSplashController();
    final booting = ValueNotifier(false);
    await tester.pumpWidget(_host(controller));
    await tester.pump(const Duration(seconds: 1));
    expect(_splash, findsOneWidget);

    controller.attach(
      _BootingApp(booting),
      bootState: booting,
      isBooting: () => booting.value,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('app'), findsOneWidget);
    expect(_splash, findsOneWidget);

    booting.value = false;
    await tester.pump();
    // Held for the settle period so the start page can finish rendering.
    await tester.pump(const Duration(milliseconds: 900));
    expect(_splash, findsOneWidget);

    // Settles only once the splash is gone and its ticker has stopped.
    await tester.pumpAndSettle();
    expect(_splash, findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('dismisses a settle after the first frame if not booting', (
    tester,
  ) async {
    final controller = LaunchSplashController();
    await tester.pumpWidget(_host(controller));
    controller.attach(
      const Text('app'),
      bootState: ValueNotifier(false),
      isBooting: () => false,
    );
    await tester.pump();
    await tester.pump();
    // Settles only once the splash is gone and its ticker has stopped.
    await tester.pumpAndSettle();
    expect(_splash, findsNothing);
  });

  testWidgets('matches the native logo size when the app density differs', (
    tester,
  ) async {
    // Android TV: the system splash is drawn at 2.0x, but MainActivity forces
    // the app to 1.0x - the logo must be twice as many logical pixels.
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(LaunchSplashController(), launchDensity: 2));
    expect(_paintedLogoSize(tester), 204);
  });

  testWidgets('uses the native size as-is without a launch density', (
    tester,
  ) async {
    await tester.pumpWidget(_host(LaunchSplashController()));
    expect(_paintedLogoSize(tester), 102);
  });

  testWidgets('gives up waiting after maxHold', (tester) async {
    final controller = LaunchSplashController();
    await tester.pumpWidget(
      _host(controller, maxHold: const Duration(seconds: 3)),
    );
    controller.attach(
      const Text('app'),
      bootState: ValueNotifier(true),
      isBooting: () => true,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(_splash, findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    // Settles only once the splash is gone and its ticker has stopped.
    await tester.pumpAndSettle();
    expect(_splash, findsNothing);
  });
}
