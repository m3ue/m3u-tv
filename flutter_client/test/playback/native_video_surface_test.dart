import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/native_video_surface.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

void main() {
  testWidgets('active native plane has no black surface wrapper', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NativeVideoSurface(
          textureId: null,
          platformView: null,
          nativePlane: _FakeNativePlane(usesNativePlane: true),
          aspectRatio: 16 / 9,
        ),
      ),
    );

    final blackBoxes = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .where((box) => box.color == Colors.black);
    expect(blackBoxes, isEmpty);
  });

  testWidgets('texture surface retains its black backing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NativeVideoSurface(
          textureId: 42,
          platformView: null,
          aspectRatio: 16 / 9,
        ),
      ),
    );

    expect(
      tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((box) => box.color == Colors.black),
      isNotEmpty,
    );
  });

  testWidgets('inactive native provider retains startup black backing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NativeVideoSurface(
          textureId: null,
          platformView: null,
          nativePlane: _FakeNativePlane(usesNativePlane: false),
          aspectRatio: 16 / 9,
        ),
      ),
    );

    expect(
      tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((box) => box.color == Colors.black),
      isNotEmpty,
    );
  });

  testWidgets('native plane hides while its route is transitioning', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final stablePlane = _RecordingNativePlane();
    final transitioningPlane = _RecordingNativePlane();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: NativeVideoSurface(
          textureId: null,
          platformView: null,
          nativePlane: stablePlane,
          aspectRatio: 16 / 9,
        ),
      ),
    );
    await tester.pump();

    expect(stablePlane.rects, isNotEmpty);
    expect(stablePlane.rects.last.isVisible, isTrue);

    unawaited(
      navigatorKey.currentState!.push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(seconds: 1),
          reverseTransitionDuration: const Duration(seconds: 1),
          pageBuilder: (_, _, _) => NativeVideoSurface(
            textureId: null,
            platformView: null,
            nativePlane: transitioningPlane,
            aspectRatio: 16 / 9,
          ),
          transitionsBuilder: (_, animation, _, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(transitioningPlane.rects, isNotEmpty);
    expect(transitioningPlane.rects.last.isVisible, isFalse);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    final completedRect = transitioningPlane.rects.last;
    expect(completedRect.isVisible, isTrue);
    expect(completedRect.x, greaterThanOrEqualTo(0));
    expect(completedRect.y, greaterThanOrEqualTo(0));
    expect(
      completedRect.x + completedRect.width,
      lessThanOrEqualTo(tester.view.physicalSize.width),
    );
    expect(
      completedRect.y + completedRect.height,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );

    navigatorKey.currentState!.pop();

    expect(transitioningPlane.rects.last.isVisible, isFalse);
  });
}

class _FakeNativePlane implements NativePlaneProvider {
  const _FakeNativePlane({required this.usesNativePlane});

  @override
  final bool usesNativePlane;

  @override
  void reportVideoRect(
    double x,
    double y,
    double width,
    double height,
    double devicePixelRatio,
  ) {}
}

class _RecordingNativePlane implements NativePlaneProvider {
  final rects = <_ReportedRect>[];

  @override
  bool get usesNativePlane => true;

  @override
  void reportVideoRect(
    double x,
    double y,
    double width,
    double height,
    double devicePixelRatio,
  ) {
    rects.add(_ReportedRect(x, y, width, height));
  }
}

class _ReportedRect {
  const _ReportedRect(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  bool get isVisible => width > 0 && height > 0;
}
