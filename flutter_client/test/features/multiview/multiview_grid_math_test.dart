import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/multiview/multiview_grid_math.dart';

void main() {
  group('multiviewGridColumns', () {
    test('single stream is 1 column', () {
      expect(multiviewGridColumns(1), 1);
    });

    test('2-4 streams form a 2-wide grid', () {
      expect(multiviewGridColumns(2), 2);
      expect(multiviewGridColumns(3), 2);
      expect(multiviewGridColumns(4), 2);
    });

    test('5-9 streams form a 3-wide grid', () {
      expect(multiviewGridColumns(5), 3);
      expect(multiviewGridColumns(9), 3);
    });
  });

  group('multiviewSwapTarget', () {
    test('moves right within a row', () {
      final target = multiviewSwapTarget(
        index: 0,
        itemCount: 4,
        direction: TraversalDirection.right,
      );
      expect(target, 1);
    });

    test('refuses to move left past the first column', () {
      final target = multiviewSwapTarget(
        index: 0,
        itemCount: 4,
        direction: TraversalDirection.left,
      );
      expect(target, isNull);
    });

    test('refuses to move right past the last column', () {
      // 4 streams -> 2 columns; index 1 is the right edge of row 0.
      final target = multiviewSwapTarget(
        index: 1,
        itemCount: 4,
        direction: TraversalDirection.right,
      );
      expect(target, isNull);
    });

    test('moves down a full row', () {
      // 9 streams -> 3 columns; index 0 down should land on index 3.
      final target = multiviewSwapTarget(
        index: 0,
        itemCount: 9,
        direction: TraversalDirection.down,
      );
      expect(target, 3);
    });

    test('refuses to move down into a short last row', () {
      // 7 streams -> 3 columns, 3 rows (3/3/1). Index 4 (row 1, col 1) down
      // would land on index 7, which doesn't exist.
      final target = multiviewSwapTarget(
        index: 4,
        itemCount: 7,
        direction: TraversalDirection.down,
      );
      expect(target, isNull);
    });

    test('moves up out of the last row', () {
      final target = multiviewSwapTarget(
        index: 6,
        itemCount: 7,
        direction: TraversalDirection.up,
      );
      expect(target, 3);
    });
  });

  group('multiviewPipCornerAfter', () {
    test('vertical presses only change the top/bottom edge', () {
      expect(
        multiviewPipCornerAfter(
          MultiviewPipCorner.bottomRight,
          TraversalDirection.up,
        ),
        MultiviewPipCorner.topRight,
      );
      expect(
        multiviewPipCornerAfter(
          MultiviewPipCorner.topLeft,
          TraversalDirection.down,
        ),
        MultiviewPipCorner.bottomLeft,
      );
    });

    test('horizontal presses only change the left/right edge', () {
      expect(
        multiviewPipCornerAfter(
          MultiviewPipCorner.bottomRight,
          TraversalDirection.left,
        ),
        MultiviewPipCorner.bottomLeft,
      );
      expect(
        multiviewPipCornerAfter(
          MultiviewPipCorner.topLeft,
          TraversalDirection.right,
        ),
        MultiviewPipCorner.topRight,
      );
    });

    test('repeating the same direction is idempotent', () {
      expect(
        multiviewPipCornerAfter(
          MultiviewPipCorner.bottomRight,
          TraversalDirection.right,
        ),
        MultiviewPipCorner.bottomRight,
      );
    });
  });
}
