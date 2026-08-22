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
