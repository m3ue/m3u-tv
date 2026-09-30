import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:m3u_tv/shared/media_browsing_widgets.dart';

// devicePixelRatio 1, so the expected decode size is just the layout size
// times ImageQualityScope's default (quality-mode) 2x oversample.
Widget _harness(Widget child) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(),
    child: Center(child: child),
  ),
);

ResizeImage _decodedImage(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  expect(image.image, isA<ResizeImage>());
  return image.image as ResizeImage;
}

void main() {
  testWidgets('unsized image decodes at its layout size, not source size', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const SizedBox(
          width: 150,
          height: 225,
          child: ResilientMediaImage(
            imageUrl: 'https://example.com/poster.jpg',
            fallbackIcon: Icons.movie,
          ),
        ),
      ),
    );

    final resize = _decodedImage(tester);
    expect(resize.width, 300);
    expect(resize.height, 450);
  });

  testWidgets('explicit width and height still drive the decode size', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const ResilientMediaImage(
          imageUrl: 'https://example.com/poster.jpg',
          fallbackIcon: Icons.movie,
          width: 100,
          height: 150,
        ),
      ),
    );

    final resize = _decodedImage(tester);
    expect(resize.width, 200);
    expect(resize.height, 300);
  });
}
