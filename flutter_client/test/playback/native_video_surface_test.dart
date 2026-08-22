import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:m3u_tv/playback/native_video_surface.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

void main() {
  testWidgets('active native plane does not paint an opaque black background', (
    tester,
  ) async {
    await tester.pumpWidget(_surface(nativePlane: _ActiveNativePlane()));

    expect(_blackBackgrounds(), findsNothing);
  });

  testWidgets('texture path retains its opaque black background', (
    tester,
  ) async {
    await tester.pumpWidget(_surface(textureId: 7));

    expect(find.byType(Texture), findsOneWidget);
    expect(_blackBackgrounds(), findsOneWidget);
  });
}

Widget _surface({int? textureId, NativePlaneProvider? nativePlane}) {
  return MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: NativeVideoSurface(
        textureId: textureId,
        platformView: null,
        nativePlane: nativePlane,
        aspectRatio: 16 / 9,
      ),
    ),
  );
}

Finder _blackBackgrounds() {
  return find.descendant(
    of: find.byType(NativeVideoSurface),
    matching: find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color == Colors.black,
    ),
  );
}

class _ActiveNativePlane implements NativePlaneProvider {
  @override
  bool get usesNativePlane => true;

  @override
  void reportVideoRect(
    double x,
    double y,
    double width,
    double height,
    double devicePixelRatio,
  ) {}
}
