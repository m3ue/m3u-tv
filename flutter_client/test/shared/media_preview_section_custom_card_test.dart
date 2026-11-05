import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<Size> cardSize(WidgetTester tester, double screenWidth) async {
    tester.view
      ..physicalSize = Size(screenWidth, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Size? size;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaPreviewSection.builder(
            title: 'Games',
            emptyLabel: 'None',
            itemCount: 1,
            baseCardWidth: 340,
            baseCardHeight: 176,
            itemBuilder: (context, index, cardSize, {required autofocus}) {
              size = cardSize;
              return SizedBox.fromSize(size: cardSize);
            },
          ),
        ),
      ),
    );
    return size!;
  }

  testWidgets('a custom card leaves a phone room to show it whole', (
    tester,
  ) async {
    final size = await cardSize(tester, 402);

    const rowWidth = 402 - MediaBrowsingMetrics.pagePadding * 2;
    expect(size.width, lessThan(rowWidth));
    expect(size.width, rowWidth * 0.9);
  });

  testWidgets('a wide screen keeps the card at its own size', (tester) async {
    final size = await cardSize(tester, 1920);

    expect(size.width, 340);
  });
}
